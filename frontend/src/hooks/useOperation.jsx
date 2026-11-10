import { useState } from "react";
import ActionForm from "../components/ActionForm";
import { Alert, Modal } from "../components/ui";
export default function useOperation(onComplete) {
  const [operation, setOperation] = useState(null); const [message, setMessage] = useState(""); const [busy, setBusy] = useState(false);
  const open = (value) => { setMessage(""); setOperation(value); };
  return { open, message, setMessage,
    notice: <Alert type="success" onClose={() => setMessage("")}>{message}</Alert>,
    dialog: operation && <Modal title={operation.title} description={operation.description} onClose={() => { if (!busy) setOperation(null); }} closable={!busy} wide={operation.wide}><ActionForm {...operation} onBusyChange={setBusy} onCancel={() => { if (!busy) setOperation(null); }} onSuccess={(result) => {
      const savedMessage = result?.message || "Đã lưu thay đổi.";
      const refreshWarning = `${savedMessage} Danh sách chưa cập nhật; hãy làm mới để xem kết quả.`;
      setMessage(savedMessage);
      setOperation(null);
      try {
        const pendingRefresh = onComplete?.(result);
        if (pendingRefresh?.catch) pendingRefresh.catch(() => setMessage(refreshWarning));
      } catch { setMessage(refreshWarning); }
    }} /></Modal>,
  };
}
