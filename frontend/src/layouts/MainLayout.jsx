import Header from "../components/Header.jsx";
import Sidebar from "../components/Sidebar.jsx";

function MainLayout({ children }) {
  return (
    <div className="app-layout">
      <Header />

      <div className="app-body">
        <Sidebar />
        <div className="app-content">{children}</div>
      </div>
    </div>
  );
}

export default MainLayout;
