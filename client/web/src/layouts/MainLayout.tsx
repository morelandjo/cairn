import { Outlet } from "react-router-dom";
import ServerSidebar from "../components/ServerSidebar.tsx";
import ChannelSidebar from "../components/ChannelSidebar.tsx";
import MemberList from "../components/MemberList.tsx";
import VoiceConnectionBar from "../components/VoiceConnectionBar.tsx";

export default function MainLayout() {
  return (
    <div className="main-layout">
      <ServerSidebar />
      <ChannelSidebar />
      <div className="main-content">
        <Outlet />
        <VoiceConnectionBar />
      </div>
      <MemberList />
    </div>
  );
}
