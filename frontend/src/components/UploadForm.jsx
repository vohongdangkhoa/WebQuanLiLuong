import { useState } from "react";
import { apiPost, apiUpload } from "../services/api";
import { Alert, Button, Field } from "./ui";
export default function UploadForm({ endpoint, json = false, example, onSuccess, onCancel, label = "Nhập dữ liệu từ tệp", description }) {
  const [file, setFile] = useState(null); const [busy, setBusy] = useState(false); const [error, setError] = useState("");
  async function submit(event) {
    event.preventDefault();
    if (!file || busy) return;
    if (file.size > 2 * 1024 * 1024) {
      setError("Dung lượng tệp không được vượt quá 2 MB.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      let result;
      if (json) {
        const bytes = await file.arrayBuffer();
        let content;
        try {
          content = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
        } catch {
          throw new Error("Tệp CSV cần dùng mã hóa UTF-8 hợp lệ.");
        }
        result = await apiPost(endpoint, { fileName: file.name, content });
      } else {
        result = await apiUpload(endpoint, file);
      }
      onSuccess(result);
    } catch (failure) {
      setError(failure.message);
    } finally {
      setBusy(false);
    }
  }
  return <form onSubmit={submit}><p className="section-note">{description}</p><div className="upload-box"><Field label="Tệp CSV (UTF-8, tối đa 2 MB)">{(id) => <input id={id} type="file" accept=".csv,text/csv" required disabled={busy} onChange={(event) => { setFile(event.target.files?.[0] || null); setError(""); }} />}</Field></div>{example && <><p className="section-note">Cấu trúc tệp:</p><pre className="pre-example">{example}</pre></>}<Alert>{error}</Alert><div className="form-actions"><Button variant="secondary" disabled={busy} onClick={onCancel}>Hủy</Button><Button type="submit" disabled={busy || !file} icon="check">{busy ? "Đang nhập…" : label}</Button></div></form>;
}
