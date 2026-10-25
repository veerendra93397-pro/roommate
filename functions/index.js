// RoomMate – sends push notifications to the phones of room members.
//
// IMPORTANT: set REGION to the same location as your Firestore database
// (Firebase Console > Firestore Database > Data tab > location shown at the top,
// e.g. "asia-south1" for Mumbai).
const REGION = "asia-south1";

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: REGION, maxInstances: 5 });

const db = admin.firestore();

/** Sends one push message to every phone registered by the given users. */
async function sendToUsers(uids, title, body, data = {}) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return;

  const userDocs = await Promise.all(unique.map((u) => db.doc(`users/${u}`).get()));
  const tokens = [];
  const tokenOwner = {};
  for (const doc of userDocs) {
    for (const t of doc.data()?.fcmTokens || []) {
      tokens.push(t);
      tokenOwner[t] = doc.ref;
    }
  }
  if (tokens.length === 0) return;

  const res = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
    android: { priority: "high" },
  });

  // Forget tokens of phones where the app was uninstalled.
  const dead = [];
  res.responses.forEach((r, i) => {
    const code = r.error && r.error.code;
    if (
      !r.success &&
      (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token")
    ) {
      dead.push(tokens[i]);
    }
  });
  await Promise.all(
    dead.map((t) =>
      tokenOwner[t].update({ fcmTokens: admin.firestore.FieldValue.arrayRemove(t) })
    )
  );
}

// 1) Anything that appears in a room's notification list is pushed to the other members
//    (new expense, payment, announcement, new member, ...).
exports.onRoomNotification = onDocumentCreated(
  "rooms/{roomId}/notifications/{id}",
  async (event) => {
    const n = event.data && event.data.data();
    if (!n) return;
    const room = await db.doc(`rooms/${event.params.roomId}`).get();
    if (!room.exists) return;

    const members = (room.data().memberIds || []).filter((u) => u !== n.by);
    await sendToUsers(members, n.title || "RoomMate", n.subtitle || "", {
      roomId: event.params.roomId,
      type: String(n.type || "other"),
    });
  }
);

// 2) Someone asked to join: tell the room owner.
exports.onJoinRequest = onDocumentCreated(
  "rooms/{roomId}/joinRequests/{uid}",
  async (event) => {
    const req = event.data && event.data.data();
    if (!req) return;
    const room = await db.doc(`rooms/${event.params.roomId}`).get();
    if (!room.exists) return;
    await sendToUsers(
      [room.data().ownerId],
      "New join request",
      `${req.name || "Someone"} wants to join ${room.data().name || "your room"}`,
      { roomId: event.params.roomId, type: "joinRequest" }
    );
  }
);

// 3) The owner answered a join request: tell the person who asked.
exports.onJoinRequestAnswered = onDocumentUpdated(
  "rooms/{roomId}/joinRequests/{uid}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after || before.status === after.status) return;
    const room = await db.doc(`rooms/${event.params.roomId}`).get();
    const roomName = (room.exists && room.data().name) || "the room";

    if (after.status === "approved") {
      await sendToUsers([event.params.uid], "Request accepted", `You can now enter ${roomName}`, {
        type: "joinApproved",
      });
    } else if (after.status === "rejected") {
      await sendToUsers([event.params.uid], "Request declined", `The owner of ${roomName} declined your request`, {
        type: "joinRejected",
      });
    }
  }
);

// 4) A new chat message: push it to everyone in the room except the sender.
exports.onChatMessage = onDocumentCreated(
  "rooms/{roomId}/messages/{id}",
  async (event) => {
    const m = event.data && event.data.data();
    if (!m) return;
    const room = await db.doc(`rooms/${event.params.roomId}`).get();
    if (!room.exists) return;
    const others = (room.data().memberIds || []).filter((u) => u !== m.authorId);
    const text = String(m.text || "");
    await sendToUsers(
      others,
      `${m.authorName || "Someone"} · ${room.data().name || "RoomMate"}`,
      text.length > 120 ? text.slice(0, 117) + "..." : text,
      { roomId: event.params.roomId, type: "chat" }
    );
  }
);
