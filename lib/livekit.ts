import { DataPacket_Kind, RoomServiceClient } from 'livekit-server-sdk';

const apiKey = process.env.LIVEKIT_API_KEY!;
const apiSecret = process.env.LIVEKIT_API_SECRET!;
const livekitUrl = process.env.LIVEKIT_URL!;

export const roomService = new RoomServiceClient(livekitUrl, apiKey, apiSecret);

/**
 * Broadcasts a message to a LiveKit room.
 * @param roomName The name of the room to broadcast to.
 * @param message The string message to broadcast.
 */
export async function broadcastToRoom(roomName: string, message: string) {
    try {
        const encoder = new TextEncoder();
        const data = encoder.encode(message);

        await roomService.sendData(roomName, data, DataPacket_Kind.RELIABLE);
        console.log(`[LiveKit] Broadcast to ${roomName}: ${message}`);
    } catch (error) {
        console.error(`[LiveKit] Broadcast error in ${roomName}:`, error);
    }
}
