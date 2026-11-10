import { useState } from "react";
import { Outlet } from "react-router";
import Header from "../components/Header";
import Sidebar from "../components/Sidebar";
export default function MainLayout() { const [menuOpen, setMenuOpen] = useState(false); return <div className={`app-layout ${menuOpen ? "menu-open" : ""}`}><a className="skip-link" href="#main-content">Đến nội dung chính</a><Sidebar onNavigate={() => setMenuOpen(false)} />{menuOpen && <button className="sidebar-backdrop" type="button" aria-label="Đóng menu" onClick={() => setMenuOpen(false)} />}<div className="app-workspace"><Header onMenu={() => setMenuOpen(!menuOpen)} /><main id="main-content" className="app-content"><Outlet /></main><footer className="app-footer">HRFlow · Hệ thống quản lý nhân sự và tiền lương<span>Dữ liệu nhất quán. Quy trình rõ ràng.</span></footer></div></div>; }
