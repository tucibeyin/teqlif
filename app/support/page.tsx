import { Navbar } from "@/components/Navbar";
import SupportContent from "./SupportContent";

export default function SupportPage() {
    return (
        <main className="min-h-screen bg-gray-50 flex flex-col">
            <Navbar />
            <SupportContent />
        </main>
    );
}
