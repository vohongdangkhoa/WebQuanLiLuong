import { useCallback, useEffect, useState } from "react";
import { apiGet } from "../services/api";

export default function useResource(path, enabled = true) {
  const [version, setVersion] = useState(0);
  const [state, setState] = useState({ path: null, version: -1, data: null, error: "" });
  const reload = useCallback(() => setVersion((value) => value + 1), []);
  const setData = useCallback((update) => setState((previous) => ({
    path, version, error: "", data: typeof update === "function" ? update(previous.data) : update,
  })), [path, version]);
  useEffect(() => {
    if (!enabled || !path) return undefined;
    const controller = new AbortController();
    apiGet(path, { signal: controller.signal }).then((data) => {
      if (!controller.signal.aborted) setState({ path, version, data, error: "" });
    }).catch((error) => {
      if (!controller.signal.aborted) setState({ path, version, data: null, error: error.message });
    });
    return () => controller.abort();
  }, [path, enabled, version]);
  const active = Boolean(enabled && path);
  const samePath = state.path === path;
  const settled = samePath && state.version === version;
  return { data: active && samePath ? state.data : null,
    loading: active && !settled, error: active && settled ? state.error : "", reload, setData };
}
