import { useState, useCallback } from "react";
import { useChat, useRoomContext } from "@livekit/components-react";
import { useSession } from "next-auth/react";
import type { ArenaMessage } from "../types";
import { censorProfanity } from "@/lib/profanity";

const MAX_MESSAGES = 50;

export function useArenaChat() {
    const room = useRoomContext();
    const { data: session } = useSession();
    const [messages, setMessages] = useState<ArenaMessage[]>([]);
    const [inputValue, setInputValue] = useState("");

    const addMessage = useCallback((msg: ArenaMessage) => {
        setMessages(prev => [...prev.slice(-(MAX_MESSAGES - 1)), msg]);
    }, []);

    const onChatMessage = useCallback((data: any) => {
        addMessage({
            id: Date.now().toString() + Math.random(),
            text: censorProfanity(data.text ?? ""),
            sender: data.senderName ?? "Katılımcı",
            senderId: data.senderId,
        });
    }, [addMessage]);

    const sendMessage = useCallback(async () => {
        const text = inputValue.trim();
        if (!text || !room) return;

        const censoredText = censorProfanity(text);

        const payload = {
            type: "CHAT",
            text: censoredText,
            senderName: session?.user?.name ?? "Katılımcı",
            senderId: session?.user?.id,
        };
        await room.localParticipant.publishData(
            new TextEncoder().encode(JSON.stringify(payload)),
            { reliable: true }
        );
        // Local echo
        addMessage({
            id: Date.now().toString(),
            text: censoredText,
            sender: session?.user?.name ?? "Sen",
            senderId: session?.user?.id,
        });
        setInputValue("");
    }, [inputValue, room, session, addMessage]);

    return { messages, inputValue, setInputValue, sendMessage, onChatMessage, addMessage };
}
