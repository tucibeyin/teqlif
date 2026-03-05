"use client";

import type { Reaction } from "../types";

const EMOJIS = ["❤️", "🔥", "😍", "💸", "👏"];

// ── Flying emoji overlay on video ─────────────────────────────────────────
interface FlyingEmojisProps {
  reactions: Reaction[];
}

export function FlyingEmojis({ reactions }: FlyingEmojisProps) {
  return (
    <>
      <style>{`
        @keyframes tq-floatUp {
          0%   { transform: translateY(0) scale(1) rotate(0deg); opacity: 1; }
          60%  { opacity: 0.9; }
          100% { transform: translateY(-260px) scale(1.7) rotate(8deg); opacity: 0; }
        }
      `}</style>
      {reactions.map(r => (
        <div
          key={r.id}
          style={{
            position: "absolute", bottom: "15%", left: `${r.left}%`,
            fontSize: "2.5rem", pointerEvents: "none", zIndex: 300,
            animation: "tq-floatUp 2.6s cubic-bezier(0.25,0.46,0.45,0.94) forwards",
            filter: "drop-shadow(0 0 10px rgba(255,255,255,0.35))",
          }}
        >
          {r.emoji}
        </div>
      ))}
    </>
  );
}

// ── Reaction bar — vertical (viewer right-edge) or horizontal (host panel) ─
interface ReactionBarProps {
  onReact: (emoji: string) => void;
  vertical?: boolean;
}

export function ReactionBar({ onReact, vertical = false }: ReactionBarProps) {
  return (
    <>
      <style>{`
        .tq-emoji-btn {
          width: 44px; height: 44px; border-radius: 50%;
          background: rgba(14,20,34,0.72);
          border: 1px solid rgba(255,255,255,0.09);
          backdrop-filter: blur(16px);
          font-size: 20px; cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          transition: all 0.15s; user-select: none;
          box-shadow: 0 3px 12px rgba(0,0,0,0.35);
        }
        .tq-emoji-btn:hover {
          background: rgba(255,255,255,0.12);
          transform: scale(1.18);
          box-shadow: 0 4px 18px rgba(0,0,0,0.5);
        }
        .tq-emoji-btn:active { transform: scale(0.9); }
      `}</style>
      <div style={{
        display: "flex",
        flexDirection: vertical ? "column" : "row",
        gap: vertical ? 8 : 6,
      }}>
        {EMOJIS.map(emoji => (
          <button
            key={emoji}
            className="tq-emoji-btn"
            onClick={() => onReact(emoji)}
          >
            {emoji}
          </button>
        ))}
      </div>
    </>
  );
}
