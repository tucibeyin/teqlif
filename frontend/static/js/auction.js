/* auction.js — Real-time açık artırma (WebSocket) */

const Auction = (() => {
    let _ws = null;
    let _streamId = null;
    let _isHost = false;
    let _onState = null;

    const STATUS_LABELS = {
        idle: 'Bekleniyor',
        active: 'Aktif',
        paused: 'Duraklatıldı',
        ended: 'Tamamlandı',
    };

    function connect(streamId, isHost, onState) {
        _streamId = streamId;
        _isHost = isHost;
        _onState = onState;

        const proto = location.protocol === 'https:' ? 'wss' : 'ws';
        _ws = new WebSocket(`${proto}://${location.host}/api/auction/${streamId}/ws`);

        _ws.onmessage = (e) => {
            const msg = JSON.parse(e.data);
            if (msg.type === 'state' && _onState) _onState(msg);
        };

        _ws.onclose = () => {
            // 3 saniye sonra yeniden bağlan (yayın devam ediyorsa)
            setTimeout(() => {
                if (_streamId) connect(_streamId, _isHost, _onState);
            }, 3000);
        };
    }

    function disconnect() {
        _streamId = null;
        if (_ws) { _ws.close(); _ws = null; }
    }

    async function startAuction(itemName, startPrice, listingId) {
        const body = listingId
            ? { listing_id: listingId }
            : { item_name: itemName, start_price: parseFloat(startPrice) };
        return await apiFetch(`/auction/${_streamId}/start`, {
            method: 'POST',
            body: JSON.stringify(body),
        });
    }

    async function pauseAuction() {
        return await apiFetch(`/auction/${_streamId}/pause`, { method: 'POST' });
    }

    async function resumeAuction() {
        return await apiFetch(`/auction/${_streamId}/resume`, { method: 'POST' });
    }

    async function endAuction() {
        return await apiFetch(`/auction/${_streamId}/end`, { method: 'POST' });
    }

    async function placeBid(amount) {
        return await apiFetch(`/auction/${_streamId}/bid`, {
            method: 'POST',
            body: JSON.stringify({ amount: parseFloat(amount) }),
        });
    }

    return { connect, disconnect, startAuction, pauseAuction, resumeAuction, endAuction, placeBid, STATUS_LABELS };
})();
