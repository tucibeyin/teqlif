"use client";

import { useTracks, VideoTrack, useConnectionState, TrackToggle, useParticipants, useRoomContext } from "@livekit/components-react";
import { Track, ConnectionState } from "livekit-client";
import { useState, useCallback } from "react";

export default function LiveVideoView({ isOwner, adOwnerName, adId }: { isOwner: boolean, adOwnerName: string, adId: string }) {
    const tracks = useTracks([Track.Source.Camera]);
    const connectionState = useConnectionState();
    const participants = useParticipants();
    const room = useRoomContext();
    const isBroadcastEnded = connectionState === ConnectionState.Disconnected;

    const handleEndBroadcast = async () => {
        if (!confirm("Yayını bitirmek istiyor musunuz?")) return;
        try {
            if (room) {
                const payload = JSON.stringify({ type: "ROOM_CLOSED" });
                await room.localParticipant.publishData(new TextEncoder().encode(payload), { reliable: true });
            }
            const res = await fetch(`/api/ads/${adId}/live`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ isLive: false }),
            });
            if (res.ok) {
                room?.disconnect();
                window.location.reload();
            }
        } catch (e) { console.error(e); }
    };

    if (isBroadcastEnded) {
        return (
            <div className="w-full h-full min-h-[400px] flex flex-col items-center justify-center bg-black text-white rounded-xl">
                <div className="text-4xl mb-4">📡</div>
                <h2 className="text-2xl font-bold">Yayın Sona Erdi</h2>
                <p className="text-white/60 mt-2">Yayıncı canlı yayını kapattı.</p>
            </div>
        );
    }

    if (tracks.length === 0) {
        return (
            <div className="w-full h-full min-h-[400px] flex flex-col items-center justify-center bg-gray-900 text-white rounded-xl animate-pulse">
                <h2 className="text-xl font-bold tracking-wider text-gray-300">Yayıncı bekleniyor...</h2>
                <p className="opacity-50 mt-2 text-sm">Lütfen ayrılmayın, açık arttırma birazdan başlayacak.</p>
            </div>
        );
    }

    const hostTrack = tracks[0];

    return (
        <div className="relative w-full h-[500px] bg-black rounded-xl overflow-hidden shadow-xl">
            {hostTrack?.publication?.isMuted ? (
                <div className="absolute inset-0 flex flex-col items-center justify-center bg-[#111]">
                    <div className="text-4xl mb-4">📷</div>
                    <div className="text-white/50 font-bold">Kamera Kapalı</div>
                </div>
            ) : (
                <VideoTrack trackRef={hostTrack} className="w-full h-full object-contain" />
            )}

            {/* Top HUD */}
            <div className="absolute top-4 left-4 right-4 z-10 flex justify-between items-start pointer-events-none">
                <div className="flex flex-col gap-2 pointer-events-auto">
                    <div className="flex items-center bg-black/50 backdrop-blur-md rounded-full p-1 pr-4 border border-white/10">
                        <div className="w-9 h-9 rounded-full bg-red-500 flex items-center justify-center font-bold text-white shadow-inner">
                            {adOwnerName.charAt(0).toUpperCase()}
                        </div>
                        <div className="ml-3 flex flex-col">
                            <span className="text-white text-sm font-bold shadow-sm">{adOwnerName}</span>
                            <span className="text-[10px] bg-red-500 text-white px-1.5 py-0.5 rounded uppercase font-black tracking-wider w-max -mt-0.5">CANLI</span>
                        </div>
                    </div>
                    <div className="flex items-center gap-1.5 bg-black/40 backdrop-blur-md px-3 py-1 rounded-full w-max border border-white/10 shadow-sm">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="white" strokeWidth="2.5"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"></path><circle cx="12" cy="12" r="3"></circle></svg>
                        <span className="text-white text-xs font-bold">{participants.length}</span>
                    </div>
                </div>

                <div className="pointer-events-auto">
                    {isOwner ? (
                        <button onClick={handleEndBroadcast} className="w-10 h-10 rounded-full bg-black/40 backdrop-blur-md border border-white/20 text-white flex items-center justify-center hover:bg-red-500 transition-colors">✕</button>
                    ) : (
                        <button onClick={() => window.location.reload()} className="w-10 h-10 rounded-full bg-black/40 backdrop-blur-md border border-white/20 text-white flex items-center justify-center hover:bg-white/20 transition-colors">✕</button>
                    )}
                </div>
            </div>

            {/* Bottom Controls for Host */}
            {isOwner && (
                <div className="absolute bottom-4 right-4 z-20 flex gap-2">
                    <TrackToggle
                        source={Track.Source.Microphone}
                        className="w-12 h-12 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-white flex items-center justify-center hover:bg-black/80 transition-all [&>svg]:w-5 [&>svg]:h-5"
                    />
                    <TrackToggle
                        source={Track.Source.Camera}
                        className="w-12 h-12 rounded-full bg-black/60 backdrop-blur-md border border-white/10 text-white flex items-center justify-center hover:bg-black/80 transition-all [&>svg]:w-5 [&>svg]:h-5"
                    />
                </div>
            )}

            {/* Bottom Gradient overlay for text visibility */}
            <div className="absolute bottom-0 left-0 right-0 h-1/3 bg-gradient-to-t from-black/80 to-transparent pointer-events-none"></div>
        </div>
    );
}
