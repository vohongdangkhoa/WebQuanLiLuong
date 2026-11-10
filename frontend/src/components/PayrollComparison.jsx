import { useState } from "react";
import useResource from "../hooks/useResource";
import { money } from "../utils/format";
import { DataTable, Modal, ResourceState, SelectField } from "./ui";

export default function PayrollComparison({ run, alternatives, onClose }) {
  const [referenceId, setReferenceId] = useState("");
  const reference = alternatives.find((row) => String(row.runId) === referenceId);
  const current = useResource("/finance/runs/" + run.runId + "/results");
  const previous = useResource(reference ? "/finance/runs/" + reference.runId + "/results" : null);
  const currentById = new Map((current.data || []).map((row) => [row.employeeId, row]));
  const previousById = new Map((previous.data || []).map((row) => [row.employeeId, row]));
  const employeeIds = new Set([...currentById.keys(), ...previousById.keys()]);
  const rows = Array.from(employeeIds, (employeeId) => {
    const before = previousById.get(employeeId);
    const after = currentById.get(employeeId);
    return {
      employeeId,
      employeeCode: (after || before).employeeCode,
      employeeName: (after || before).employeeName,
      previousNet: before?.netAmount ?? null,
      currentNet: after?.netAmount ?? null,
      change: before && after ? Number(after.netAmount) - Number(before.netAmount) : null,
    };
  }).sort((a, b) => a.employeeCode.localeCompare(b.employeeCode));
  const amount = (value) => value === null ? "—" : money(value);

  return (
    <Modal wide title={"So sánh với phiên bản " + run.versionNo} onClose={onClose}>
      <SelectField label="Phiên bản đối chiếu trong cùng kỳ" value={referenceId}
        onChange={(event) => setReferenceId(event.target.value)}
        options={alternatives.map((row) => ({ value: row.runId, label: "Phiên bản " + row.versionNo }))} />
      {reference && (
        <ResourceState resource={current}>
          <ResourceState resource={previous}>
            <p className="section-note">Chênh lệch là thực lĩnh của phiên bản đang xem trừ phiên bản đối chiếu. Dấu gạch biểu thị chưa có kết quả.</p>
            <DataTable rows={rows} rowKey="employeeId" exportName={"so-sanh-luong-" + run.runId + "-" + reference.runId + ".csv"} columns={[
              { key: "employeeCode", label: "Mã nhân viên" },
              { key: "employeeName", label: "Họ tên" },
              { key: "previousNet", label: "Thực lĩnh V" + reference.versionNo, align: "right", render: amount },
              { key: "currentNet", label: "Thực lĩnh V" + run.versionNo, align: "right", render: amount },
              { key: "change", label: "Chênh lệch", align: "right", render: amount },
            ]} />
          </ResourceState>
        </ResourceState>
      )}
    </Modal>
  );
}
