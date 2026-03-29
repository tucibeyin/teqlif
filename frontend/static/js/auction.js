/* auction.js — Real-time açık artırma (WebSocket) */

const Auction = (() => {
    let _ws = null;
    let _streamId = null;
    let _isHost = false;
    let _onState = null;

    let _pingInterval = null;

    const STATUS_LABELS = {
        idle: 'Bekleniyor',
        active: 'Aktif',
        paused: 'Duraklatıldı',
        ended: 'Tamamlandı',
        buy_it_now_pending: 'Onay Bekleniyor',
    };

    function connect(streamId, isHost, onState) {
        _streamId = streamId;
        _isHost = isHost;
        _onState = onState;

        const proto = location.protocol === 'https:' ? 'wss' : 'ws';
        _ws = new WebSocket(`${proto}://${location.host}/api/auction/${streamId}/ws`);

        _ws.onopen = () => {
            clearInterval(_pingInterval);
            _pingInterval = setInterval(() => {
                if (_ws && _ws.readyState === WebSocket.OPEN) {
                    try { _ws.send('ping'); } catch (_) {}
                }
            }, 30000);
        };

        _ws.onmessage = (e) => {
            try {
                const msg = JSON.parse(e.data);
                if ((msg.type === 'state' || msg.type === 'auction_ended_by_buy_it_now'
                     || msg.type === 'buy_it_now_requested' || msg.type === 'buy_it_now_rejected') && _onState) {
                    _onState(msg);
                }
            } catch (err) {
                console.error('[Auction] WS mesajı ayrıştırılamadı:', err);
            }
        };

        _ws.onclose = () => {
            clearInterval(_pingInterval);
            // 3 saniye sonra yeniden bağlan (yayın devam ediyorsa)
            setTimeout(() => {
                if (_streamId) connect(_streamId, _isHost, _onState);
            }, 3000);
        };
    }

    function disconnect() {
        clearInterval(_pingInterval);
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

    async function acceptBuyItNow() {
        return await apiFetch(`/auction/${_streamId}/buy-it-now/accept`, { method: 'POST' });
    }

    async function rejectBuyItNow() {
        return await apiFetch(`/auction/${_streamId}/buy-it-now/reject`, { method: 'POST' });
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

    return { connect, disconnect, startAuction, pauseAuction, resumeAuction, endAuction, placeBid, acceptBid, buyItNow, acceptBuyItNow, rejectBuyItNow, STATUS_LABELS };
})();
