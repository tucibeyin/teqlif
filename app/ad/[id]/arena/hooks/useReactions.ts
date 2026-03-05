import { useState, useCallback, useRef } from "react";
import { useRoomContext } from "@livekit/components-react";
import { useSession } from "next-auth/react";
import type { Reaction } from "../types";

const RATE_LIMIT_MS = 500;
const MAX_REACTIONS = 15;
const REACTION_TTL_MS = 2500;

export function useReactions() {
    const room = useRoomContext();
    const { data: session } = useSession();
    const [reactions, setReactions] = useState<Reaction[]>([]);
    const lastReactionTimeRef = useRef(0);

    const addReaction = useCallback((emoji: string) => {
        const reaction: Reaction = {
            id: Date.now().toString() + Math.random(),
            emoji,
            left: Math.random() * 15 + 75, // 75%–90% from left
        };
        setReactions(prev => [...prev.slice(-(MAX_REACTIONS - 1)), reaction]);
        setTimeout(() => {
            setReactions(prev => prev.filter(r => r.id !== reaction.id));
        }, REACTION_TTL_MS);
    }, []);

    const sendReaction = useCallback(async (emoji: string) => {
        const now = Date.now();
        if (now - lastReactionTimeRef.current < RATE_LIMIT_MS) return;
        lastReactionTimeRef.current = now;
        if (!room) return;
        try {
            const payload = JSON.stringify({ type: "REACTION", emoji, userId: session?.user?.id });
            await room.localParticipant.publishData(
                new TextEncoder().encode(payload),
                { reliable: true }
            );
            addReaction(emoji); // Local echo
        } catch (e) {
            console.error("Reaction send error:", e);
        }
    }, [room, session, addReaction]);

    return { reactions, addReaction, sendReaction };
}
