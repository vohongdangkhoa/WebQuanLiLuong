import { useState } from "react";
import useOperation from "../hooks/useOperation";
import useResource from "../hooks/useResource";
import { Button, DataTable, Modal, ResourceState, StatusBadge, Tabs } from "./ui";

export default function OrganizationCatalog({ onClose, onSaved }) {
  const [kind, setKind] = useState("departments");
  const label = kind === "departments" ? "phòng ban" : "chức danh";
  const endpoint = "/hr/organization/" + kind;
  const catalog = useResource(endpoint);
  const operation = useOperation(() => {
    catalog.reload();
    onSaved();
  });

  function edit(row) {
    operation.open({
      title: (row ? "Chỉnh sửa " : "Thêm ") + label,
      endpoint,
      fields: [
        { name: "code", label: "Mã", required: true, maxLength: 30, defaultValue: row?.code },
        { name: "name", label: "Tên", required: true, maxLength: 150, defaultValue: row?.name },
        { name: "isActive", label: "Trạng thái", type: "select", required: true, defaultValue: row?.isActive ?? "Y",
          options: [{ value: "Y", label: "Đang hoạt động" }, { value: "N", label: "Ngừng sử dụng" }] },
      ],
      transform: (values) => ({ ...values, id: row?.id ?? null }),
    });
  }

  return (
    <Modal wide title="Danh mục tổ chức" onClose={onClose}>
      <Tabs value={kind} onChange={setKind} tabs={[
        { value: "departments", label: "Phòng ban" },
        { value: "positions", label: "Chức danh" },
      ]} />
      {operation.notice}
      <div className="section-toolbar">
        <p className="section-note">Các mục ngừng sử dụng vẫn có trong lịch sử phân công.</p>
        <Button icon="plus" onClick={() => edit()}>Thêm {label}</Button>
      </div>
      <ResourceState resource={catalog}>
        <DataTable rows={catalog.data || []} rowKey="id" columns={[
          { key: "code", label: "Mã" },
          { key: "name", label: "Tên" },
          { key: "isActive", label: "Trạng thái", render: (value) => <StatusBadge value={value === "Y" ? "ACTIVE" : "INACTIVE"} /> },
        ]} actions={(row) => <Button variant="ghost" onClick={() => edit(row)}>Chỉnh sửa</Button>} />
      </ResourceState>
      {operation.dialog}
    </Modal>
  );
}
