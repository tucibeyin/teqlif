/* stream.js — LiveKit bağlantı mantığı */
/* window.LivekitClient CDN'den gelir (livekit-client.umd.min.js) */

const Stream = (() => {
    const STORAGE_KEY = 'teqlif_stream';

    function save(data) {
        sessionStorage.setItem(STORAGE_KEY, JSON.stringify(data));
    }

    function load() {
        try {
            const d = sessionStorage.getItem(STORAGE_KEY);
            return d ? JSON.parse(d) : null;
        } catch {
            return null;
        }
    }

    function clear() {
        sessionStorage.removeItem(STORAGE_KEY);
    }

    async function startStream(title) {
        const data = await apiFetch('/streams/start', {
            method: 'POST',
            body: JSON.stringify({ title }),
        });
        // data: { stream_id, room_name, livekit_url, token }
        save({ ...data, is_host: true, title });
        return data;
    }

    async function joinStream(streamId) {
        const data = await apiFetch(`/streams/${streamId}/join`, {
            method: 'POST',
        });
        // data: { stream_id, room_name, livekit_url, token, title, host_username }
        save({ ...data, is_host: false });
        return data;
    }

    async function endStream(streamId) {
        await apiFetch(`/streams/${streamId}/end`, { method: 'POST' });
    }

    async function leaveStream(streamId) {
        await apiFetch(`/streams/${streamId}/leave`, { method: 'DELETE' });
    }

    return { save, load, clear, startStream, joinStream, endStream, leaveStream };
})();


/* ── LiveKit Oda Yönetimi ── */
let _room = null;

async function connectRoom({ livekit_url, token, isHost, localVideoEl, remoteVideoEl, remoteAudioEl, onViewerCount, onDisconnect }) {
    const { Room, RoomEvent, Track } = LivekitClient;

    _room = new Room({
        adaptiveStream: true,
        dynacast: true,
    });

    // Uzak katılımcı track'i geldiğinde
    _room.on(RoomEvent.TrackSubscribed, (track, _pub, _participant) => {
        if (track.kind === Track.Kind.Video && remoteVideoEl) {
            track.attach(remoteVideoEl);
        } else if (track.kind === Track.Kind.Audio && remoteAudioEl) {
            track.attach(remoteAudioEl);
        }
    });

    _room.on(RoomEvent.TrackUnsubscribed, (track) => {
        track.detach();
    });

    _room.on(RoomEvent.Disconnected, () => {
        if (onDisconnect) onDisconnect();
    });

    // Bağlan
    await _room.connect(livekit_url, token);

    if (isHost) {
        // Kamera + Mikrofon aç
        await _room.localParticipant.setCameraEnabled(true);
        await _room.localParticipant.setMicrophoneEnabled(true);

        // Lokal önizleme
        if (localVideoEl) {
            const { Track: T } = LivekitClient;
            _room.localParticipant.on('localTrackPublished', (pub) => {
                if (pub.track && pub.track.kind === T.Kind.Video) {
                    pub.track.attach(localVideoEl);
                }
            });
            // Eğer zaten yayınlandıysa
            for (const pub of _room.localParticipant.videoTrackPublications.values()) {
                if (pub.track) pub.track.attach(localVideoEl);
            }
        }
    }

    return _room;
}

async function disconnectRoom() {
    if (_room) {
        await _room.disconnect();
        _room = null;
    }
}
