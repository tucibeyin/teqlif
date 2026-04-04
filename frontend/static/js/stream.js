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

    async function startStream(title, category) {
        const captchaToken = await getCaptchaToken();
        const data = await apiFetch('/streams/start', {
            method: 'POST',
            body: JSON.stringify({ title, category }),
            headers: captchaToken ? { 'X-Captcha-Token': captchaToken } : {},
        });
        save({ ...data, is_host: true, title, category });
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

    async function inviteCoHost(streamId, username) {
        await apiFetch(`/streams/${streamId}/cohost/invite`, {
            method: 'POST',
            body: JSON.stringify({ target_username: username }),
        });
    }

    /** Sahne davetini kabul et — yeni can_publish=true token döner.
     *  Mevcut odadan çıkar, yeni tokenla bağlanır ve local kamerayı .cohost-pip içinde gösterir. */
    async function acceptCoHostInvite(streamId) {
        const data = await apiFetch(`/streams/${streamId}/cohost/accept`, { method: 'POST' });
        // Mevcut bağlantıyı kes
        await disconnectRoom();
        // Yeni tokenla bağlan (publisher)
        const container = document.getElementById('videoContainer');
        let pipEl = container?.querySelector('.cohost-pip');
        if (!pipEl) {
            pipEl = document.createElement('div');
            pipEl.className = 'cohost-pip';
            container?.appendChild(pipEl);
        }
        const localVidEl = document.createElement('video');
        localVidEl.autoplay = true;
        localVidEl.playsInline = true;
        localVidEl.muted = true; // kendi sesini duymamalı
        pipEl.innerHTML = '';
        pipEl.appendChild(localVidEl);

        // Host identity: viewer olarak kaydedilen stream datasından al (= str(host.id))
        const hostIdentity = load()?.host_livekit_identity || null;
        const room = await connectRoom({
            livekit_url: data.livekit_url,
            token: data.token,
            isHost: true,            // can_publish=true → kamera/mikrofon aç
            hostIdentity,            // gerçek host'u doğru tanımla
            localVideoEl: localVidEl,
            remoteVideoEl: document.getElementById('mainVideo'),
            remoteAudioEl: document.getElementById('remoteAudio'),
            onDisconnect: () => {
                pipEl.remove();
            },
            onRemoteVideo: () => {},
        });
        return room;
    }

    async function removeCoHost(streamId, username) {
        await apiFetch(`/streams/${streamId}/cohost/remove`, {
            method: 'POST',
            body: JSON.stringify({ target_username: username }),
        });
    }

    return { save, load, clear, startStream, joinStream, endStream, leaveStream, inviteCoHost, acceptCoHostInvite, removeCoHost };
})();


/* ── LiveKit Oda Yönetimi ── */
var _room = null;

async function connectRoom({ livekit_url, token, isHost, hostIdentity, localVideoEl, remoteVideoEl, remoteAudioEl, onDisconnect, onRemoteVideo, onCoHostPip }) {
    const { Room, RoomEvent, Track } = LivekitClient;

    _room = new Room({
        adaptiveStream: true,
        dynacast: true,
    });

    // Host SID'ini takip et — identity bazlı belirlenir (varsa), yoksa ilk video fallback
    let _hostParticipantSid = null;

    function _isHostParticipant(participant) {
        if (hostIdentity) return participant.identity === hostIdentity;
        // Fallback: henüz host belirlenmemişse ilk video track = host
        return _hostParticipantSid === null;
    }

    function _attachCohostPip(track) {
        const container = document.getElementById('videoContainer');
        if (!container) return;
        let pipEl = container.querySelector('.cohost-pip');
        if (!pipEl) {
            pipEl = document.createElement('div');
            pipEl.className = 'cohost-pip';
            container.appendChild(pipEl);
        }
        const vidEl = document.createElement('video');
        vidEl.autoplay = true;
        vidEl.playsInline = true;
        vidEl.muted = true;
        pipEl.innerHTML = '';
        pipEl.appendChild(vidEl);
        track.attach(vidEl);
        if (onCoHostPip) onCoHostPip(pipEl);
    }

    // Uzak track geldiğinde (yeni katılanlar veya bağlantı sonrası)
    _room.on(RoomEvent.TrackSubscribed, (track, _pub, participant) => {
        console.log('[LiveKit] TrackSubscribed:', track.kind, 'participant:', participant.identity);
        if (track.kind === Track.Kind.Video) {
            if (_isHostParticipant(participant)) {
                // Host'un video track'i → ana ekrana
                _hostParticipantSid = participant.sid;
                if (remoteVideoEl) {
                    track.attach(remoteVideoEl);
                    if (onRemoteVideo) onRemoteVideo();
                }
            } else {
                // Co-host'un video track'i → PiP
                _attachCohostPip(track);
            }
        } else if (track.kind === Track.Kind.Audio) {
            if (_isHostParticipant(participant) && remoteAudioEl) {
                // Host sesi → belirlenmiş audio elementi
                track.attach(remoteAudioEl);
            } else if (!_isHostParticipant(participant)) {
                // Co-host sesi → yeni audio elementi (aynı elementa iki track bağlanamaz)
                const audioEl = track.attach();
                audioEl.autoplay = true;
                document.body.appendChild(audioEl);
            }
        }
    });

    // Track yayınlandığında ama henüz abone olunmadıysa (auto-subscribe devre dışıysa fallback)
    // Host dahil herkes için aktif — co-host publish ettiğinde host da alabilsin.
    _room.on(RoomEvent.TrackPublished, (pub, participant) => {
        console.log('[LiveKit] TrackPublished:', pub.kind, 'isSubscribed:', pub.isSubscribed, 'participant:', participant.identity);
        if (!pub.isSubscribed) {
            pub.setSubscribed(true);
        }
    });

    _room.on(RoomEvent.ConnectionStateChanged, (state) => {
        console.log('[LiveKit] ConnectionStateChanged:', state);
    });

    _room.on(RoomEvent.TrackUnsubscribed, (track, _pub, participant) => {
        const els = track.detach();
        // Otomatik oluşturulan co-host audio elementlerini DOM'dan kaldır
        els.forEach(el => {
            if (el.tagName === 'AUDIO' && el !== remoteAudioEl) el.remove();
        });
        // Co-host sahneden ayrıldıysa PiP kutusunu kaldır
        if (track.kind === Track.Kind.Video && participant && participant.sid !== _hostParticipantSid) {
            const container = document.getElementById('videoContainer');
            const pipEl = container?.querySelector('.cohost-pip');
            if (pipEl) pipEl.remove();
        }
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
    console.log('[LiveKit] Bağlandı. RemoteParticipants:', _room.remoteParticipants.size);

    if (isHost) {
        if (!hostIdentity) {
            // Gerçek host: kendi SID'i = host SID
            _hostParticipantSid = _room.localParticipant.sid;
        } else {
            // Co-host (sahneye kabul edildi): gerçek host'u identity üzerinden bul
            for (const p of _room.remoteParticipants.values()) {
                if (p.identity === hostIdentity) {
                    _hostParticipantSid = p.sid;
                    for (const pub of p.trackPublications.values()) {
                        if (pub.isSubscribed && pub.track) {
                            if (pub.track.kind === Track.Kind.Video && remoteVideoEl) {
                                pub.track.attach(remoteVideoEl);
                                if (onRemoteVideo) onRemoteVideo();
                            } else if (pub.track.kind === Track.Kind.Audio && remoteAudioEl) {
                                pub.track.attach(remoteAudioEl);
                            }
                        } else if (!pub.isSubscribed) {
                            pub.setSubscribed(true);
                        }
                    }
                }
            }
        }

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
            console.log('[LiveKit] Mevcut katılımcı:', participant.identity, '| trackPublications:', participant.trackPublications.size);
            const isHost = _isHostParticipant(participant);
            if (isHost) _hostParticipantSid = participant.sid;
            for (const pub of participant.trackPublications.values()) {
                console.log('[LiveKit] Track:', pub.kind, 'isSubscribed:', pub.isSubscribed, 'track:', !!pub.track);
                if (pub.isSubscribed && pub.track) {
                    if (pub.track.kind === Track.Kind.Video) {
                        if (isHost && remoteVideoEl) {
                            pub.track.attach(remoteVideoEl);
                            if (onRemoteVideo) onRemoteVideo();
                        } else if (!isHost) {
                            _attachCohostPip(pub.track);
                        }
                    } else if (pub.track.kind === Track.Kind.Audio) {
                        if (isHost && remoteAudioEl) {
                            pub.track.attach(remoteAudioEl);
                        } else if (!isHost) {
                            const audioEl = pub.track.attach();
                            audioEl.autoplay = true;
                            document.body.appendChild(audioEl);
                        }
                    }
                } else if (!pub.isSubscribed) {
                    pub.setSubscribed(true);
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
