const express = require("express");
const router = express.Router();
const db = require("../db");
const verifyToken = require("../middleware/authMiddleware");
const {
  notifyParent,
  getParentUnreadCount,
  ensureNotificationsTable,
} = require("../parentNotify");

// Unread count for parent bell badge
router.get("/parent/unread-count", verifyToken, async (req, res) => {
  try {
    const count = await getParentUnreadCount(req.user.id);
    res.json({ unread_count: count });
  } catch (err) {
    console.error("unread-count:", err);
    res.status(500).json({ error: "Database error", details: err.message });
  }
});

// Mark all notifications read (optional child_id in body)
router.post("/parent/mark-read", verifyToken, async (req, res) => {
  try {
    await ensureNotificationsTable();
    const childId = req.body.child_id;
    if (childId != null && childId !== "") {
      await db.query(
        `UPDATE notifications SET is_read = 1
         WHERE parent_id = ? AND child_id = ? AND (is_read = 0 OR is_read IS NULL)`,
        [req.user.id, childId]
      );
    } else {
      await db.query(
        `UPDATE notifications SET is_read = 1
         WHERE parent_id = ? AND (is_read = 0 OR is_read IS NULL)`,
        [req.user.id]
      );
    }
    const count = await getParentUnreadCount(req.user.id);
    res.json({ message: "ok", unread_count: count });
  } catch (err) {
    console.error("mark-read:", err);
    res.status(500).json({ error: "Database error", details: err.message });
  }
});

// CREATE NOTIFICATION (+ parent FCM push)
router.post("/create", verifyToken, async (req, res) => {
  try {
    const { parent_id, child_id, message, type, title } = req.body;

    if (!parent_id || !child_id || !message || !type) {
      return res.status(400).json({ message: "All fields are required" });
    }

    if (Number(parent_id) !== Number(req.user.id)) {
      return res.status(403).json({ message: "Forbidden" });
    }

    const { id, unreadCount } = await notifyParent({
      parentId: parent_id,
      childId: child_id,
      message,
      type,
      title,
    });

    const io = req.app.get("io");
    io.to(`parent_${parent_id}`).emit("parent_notification", {
      id,
      parent_id,
      child_id,
      message,
      type,
      unread_count: unreadCount,
      created_at: new Date(),
    });

    res.json({ message: "Notification created", id, unread_count: unreadCount });
  } catch (err) {
    console.error("Error creating notification:", err);
    res.status(500).json({ error: "Database error", details: err.message });
  }
});

// GET NOTIFICATIONS BY CHILD
router.get("/:child_id", verifyToken, async (req, res) => {
  try {
    const { child_id } = req.params;

    const [childRows] = await db.query(
      "SELECT id FROM children WHERE id = ? AND parent_id = ?",
      [child_id, req.user.id]
    );
    if (!childRows.length) {
      return res.status(403).json({ message: "Child not found" });
    }

    const [results] = await db.query(
      `SELECT * FROM notifications
       WHERE child_id = ? AND parent_id = ?
       ORDER BY created_at DESC`,
      [child_id, req.user.id]
    );
    res.json(results);
  } catch (err) {
    console.error("Error fetching notifications:", err);
    res.status(500).json({ error: "Database error", details: err.message });
  }
});

// DELETE
router.delete("/:id", verifyToken, async (req, res) => {
  try {
    const { id } = req.params;

    await db.query(
      `DELETE FROM notifications WHERE id = ? AND parent_id = ?`,
      [id, req.user.id]
    );
    const count = await getParentUnreadCount(req.user.id);
    res.json({ message: "Notification deleted", unread_count: count });
  } catch (err) {
    console.error("Error deleting notification:", err);
    res.status(500).json({ error: "Database error", details: err.message });
  }
});

module.exports = router;
