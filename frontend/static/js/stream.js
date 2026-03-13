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
        save({ ...data, is_host: true, title });
        return data;
    }

    async function joinStream(streamId) {
        const data = await apiFetch(`/streams/${streamId}/join`, {
            method: 'POST',
        });
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

async function connectRoom({ livekit_url, token, isHost, localVideoEl, remoteVideoEl, remoteAudioEl, onDisconnect, onRemoteVideo }) {
    const { Room, RoomEvent, Track } = LivekitClient;

    _room = new Room({
        adaptiveStream: true,
        dynacast: true,
    });

    // Uzak track geldiğinde (yeni katılanlar veya bağlantı sonrası)
    _room.on(RoomEvent.TrackSubscribed, (track, _pub, _participant) => {
        if (track.kind === Track.Kind.Video && remoteVideoEl) {
            track.attach(remoteVideoEl);
            if (onRemoteVideo) onRemoteVideo();
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

    // Viewer: kamera/mikrofonu hiç açma
    const connectOpts = isHost ? {} : {
        audio: false,
        video: false,
    };

    await _room.connect(livekit_url, token, connectOpts);

    if (isHost) {
        await _room.localParticipant.setCameraEnabled(true);
        await _room.localParticipant.setMicrophoneEnabled(true);

        if (localVideoEl) {
            _room.localParticipant.on('localTrackPublished', (pub) => {
                if (pub.track && pub.track.kind === Track.Kind.Video) {
                    pub.track.attach(localVideoEl);
                }
            });
            // Zaten yayınlandıysa hemen bağla
            for (const pub of _room.localParticipant.videoTrackPublications.values()) {
                if (pub.track) pub.track.attach(localVideoEl);
            }
        }
    } else {
        // Bağlantı sonrası mevcut yayınlanan track'leri kontrol et (race condition fix)
        for (const participant of _room.remoteParticipants.values()) {
            for (const pub of participant.trackPublications.values()) {
                if (!pub.isSubscribed || !pub.track) continue;
                if (pub.track.kind === Track.Kind.Video && remoteVideoEl) {
                    pub.track.attach(remoteVideoEl);
                    if (onRemoteVideo) onRemoteVideo();
                } else if (pub.track.kind === Track.Kind.Audio && remoteAudioEl) {
                    pub.track.attach(remoteAudioEl);
                }
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
