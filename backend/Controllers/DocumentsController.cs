using System.Globalization;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Oracle.ManagedDataAccess.Client;
using Payroll.Api.Data;
using Payroll.Api.Services;

namespace Payroll.Api.Controllers;

[ApiController, Authorize(Roles="HR,PAYROLL,DIRECTOR,EMPLOYEE"), Route("api/documents")]
[ResponseCache(NoStore=true,Location=ResponseCacheLocation.None)]
public sealed class DocumentsController(OraclePlatformRepository repository,IWebHostEnvironment environment) : ControllerBase
{
    private long Actor() => long.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier),
        NumberStyles.None,CultureInfo.InvariantCulture,out var id) && id>0
        ? id : throw new PlatformException("Phiên đăng nhập không hợp lệ.",401);

    [HttpPost,RequestSizeLimit(11*1024*1024)]
    public async Task<IActionResult> Upload([FromForm] IFormFile file,CancellationToken ct)
    {
        if(file.Length is <=0 or >10*1024*1024)
            return BadRequest(new{message="Chọn tệp PDF hoặc ảnh có dung lượng tối đa 10 MB."});
        var name=Path.GetFileName(file.FileName);
        if(name.Length>255) return BadRequest(new{message="Tên tệp tối đa 255 ký tự."});
        var extension=Path.GetExtension(name).ToLowerInvariant();
        await using var source=file.OpenReadStream();
        var header=new byte[8];var count=await source.ReadAsync(header,ct);source.Position=0;
        var mime=extension switch
        {
            ".pdf" when count>=5 && header.AsSpan(0,5).SequenceEqual("%PDF-"u8) => "application/pdf",
            ".png" when count>=8 && header.AsSpan(0,8).SequenceEqual(new byte[]{137,80,78,71,13,10,26,10}) => "image/png",
            ".jpg" or ".jpeg" when count>=3 && header[0]==255 && header[1]==216 && header[2]==255 => "image/jpeg",
            _ => null
        };
        if(mime is null) return BadRequest(new{message="Định dạng hoặc nội dung tệp không hợp lệ. Chỉ chấp nhận PDF, PNG và JPEG."});
        var folder=Path.Combine(environment.ContentRootPath,".local","uploads");Directory.CreateDirectory(folder);
        var token=Guid.NewGuid().ToString("N");var path=Path.Combine(folder,token);
        try
        {
            await using(var destination=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None,81920,true))
                await source.CopyToAsync(destination,ct);
            string sha;
            await using(var content=System.IO.File.OpenRead(path)) sha=Convert.ToHexString(await SHA256.HashDataAsync(content,ct)).ToLowerInvariant();
            var id=await repository.WriteAsync("register_file",Actor(),ct,"p_id",
                ("p_key",OracleDbType.Varchar2,"uploads/"+token),("p_name",OracleDbType.Varchar2,name),
                ("p_mime",OracleDbType.Varchar2,mime),("p_size",OracleDbType.Int64,file.Length),
                ("p_sha",OracleDbType.Varchar2,sha));
            return StatusCode(201,new{documentId=id,id,fileName=name,sha256=sha,sizeBytes=file.Length,message="Đã tải tài liệu lên."});
        }
        catch
        {
            try{System.IO.File.Delete(path);}catch(IOException){}
            throw;
        }
    }

    [HttpGet("{id:long}")]
    public async Task<IActionResult> Download(long id,CancellationToken ct)
    {
        if(id<=0) return NotFound();
        var rows=await repository.ReadAsync("document_rows",Actor(),ct,("p_id",OracleDbType.Int64,id));
        var row=rows.FirstOrDefault();
        if(row is null) return NotFound(new{message="Không tìm thấy tài liệu hoặc bạn không có quyền xem."});
        var key=Convert.ToString(row["storageKey"],CultureInfo.InvariantCulture)??"";
        if(!key.StartsWith("uploads/",StringComparison.Ordinal) || !Guid.TryParseExact(key[8..],"N",out var guid))
            return NotFound();
        var path=Path.Combine(environment.ContentRootPath,".local","uploads",guid.ToString("N"));
        if(!System.IO.File.Exists(path)) return NotFound(new{message="Tệp tài liệu hiện không còn trên máy chủ."});
        return PhysicalFile(path,"application/octet-stream",Convert.ToString(row["originalName"],CultureInfo.InvariantCulture));
    }
}
