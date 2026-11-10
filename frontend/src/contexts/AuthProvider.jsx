import { useCallback, useEffect, useState } from "react";
import AuthContext from "./AuthContext";
import { getCurrentUser, loginUser, logoutUser } from "../services/api";
export default function AuthProvider({ children }) {
  const [user, setUser] = useState(null); const [isChecking, setIsChecking] = useState(true); const [sessionError, setSessionError] = useState(""); const [retry, setRetry] = useState(0);
  useEffect(() => { let ignore = false; getCurrentUser().then((value) => { if (!ignore) setUser(value); }).catch((error) => { if (!ignore) setSessionError(error.message); }).finally(() => { if (!ignore) setIsChecking(false); }); return () => { ignore = true; }; }, [retry]);
  useEffect(() => { const expired = () => setUser(null); window.addEventListener("payroll:session-expired", expired); return () => window.removeEventListener("payroll:session-expired", expired); }, []);
  const retrySession = useCallback(() => { setIsChecking(true); setSessionError(""); setRetry((value) => value + 1); }, []);
  async function signIn(username, password) { const value = await loginUser(username.trim(), password); setUser(value); return value; }
  async function signOut() { await logoutUser(); setUser(null); }
  return <AuthContext value={{ user, isChecking, sessionError, retrySession, signIn, signOut }}>{children}</AuthContext>;
}
