/* auction.js — Real-time açık artırma (WebSocket)
 *
 * WS'den gelen her 'state' mesajı window'a 'auction-state' CustomEvent
 * olarak dispatch edilir. Alpine.js bileşenleri @auction-state.window
 * ile, vanilla JS dinleyicileri window.addEventListener ile bağlanır.
 */

const Auction = (() => {
    let _ws = null;
    let _streamId = null;
    let _isHost = false;

    const STATUS_LABELS = {
        idle: 'Bekleniyor',
        active: 'Aktif',
        paused: 'Duraklatıldı',
        ended: 'Tamamlandı',
    };

    function connect(streamId, isHost) {
        _streamId = streamId;
        _isHost = isHost;

        const proto = location.protocol === 'https:' ? 'wss' : 'ws';
        _ws = new WebSocket(`${proto}://${location.host}/api/auction/${streamId}/ws`);

        _ws.onmessage = (e) => {
            const msg = JSON.parse(e.data);
            if (msg.type === 'state') {
                // Tüm dinleyicilere (Alpine bileşenleri dahil) broadcast et
                window.dispatchEvent(new CustomEvent('auction-state', { detail: msg }));
            }
        };

        _ws.onclose = () => {
            // 3 saniye sonra yeniden bağlan (yayın devam ediyorsa)
            setTimeout(() => {
                if (_streamId) connect(_streamId, _isHost);
            }, 3000);
        };
    }

    function disconnect() {
        _streamId = null;
        if (_ws) { _ws.close(); _ws = null; }
    }

    async function startAuction(itemName, startPrice, listingId) {
        const body = listingId
            ? { listing_id: listingId, start_price: parseFloat(startPrice) }
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

    async function acceptBid() {
        return await apiFetch(`/auction/${_streamId}/accept`, { method: 'POST' });
    }

    return { connect, disconnect, startAuction, pauseAuction, resumeAuction, endAuction, placeBid, acceptBid, STATUS_LABELS };
})();
