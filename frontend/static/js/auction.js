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
            try {
                const msg = JSON.parse(e.data);
                if ((msg.type === 'state' || msg.type === 'auction_ended_by_buy_it_now') && _onState) {
                    _onState(msg);
                }
            } catch (err) {
                console.error('[Auction] WS mesajı ayrıştırılamadı:', err);
            }
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

    async function startAuction(itemName, startPrice, listingId, buyItNowPrice) {
        const body = listingId
            ? { listing_id: listingId, start_price: parseFloat(startPrice) }
            : { item_name: itemName, start_price: parseFloat(startPrice) };
        if (buyItNowPrice != null && !isNaN(buyItNowPrice) && buyItNowPrice > 0) {
            body.buy_it_now_price = parseFloat(buyItNowPrice);
        }
        return await apiFetch(`/auction/${_streamId}/start`, {
            method: 'POST',
            body: JSON.stringify(body),
        });
    }

    async function buyItNow() {
        return await apiFetch(`/auction/${_streamId}/buy-it-now`, { method: 'POST' });
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

    return { connect, disconnect, startAuction, pauseAuction, resumeAuction, endAuction, placeBid, acceptBid, buyItNow, STATUS_LABELS };
})();
