import type {
  MeetingContext,
  MeetingContextStore,
} from "./types";

interface MeetingContextRow {
  meeting_id: string;
  media_placement_json: string;
  media_region: string | null;
  created_at: number;
  expires_at: number;
}

export class D1MeetingContextStore implements MeetingContextStore {
  constructor(private readonly database: D1Database) {}

  async get(meetingId: string): Promise<MeetingContext | null> {
    const row = await this.database
      .prepare(
        `SELECT meeting_id, media_placement_json, media_region, created_at, expires_at
         FROM meeting_context
         WHERE meeting_id = ?1`,
      )
      .bind(meetingId)
      .first<MeetingContextRow>();

    if (row === null) {
      return null;
    }

    let decodedPlacement: unknown;
    try {
      decodedPlacement = JSON.parse(row.media_placement_json) as unknown;
    } catch (error: unknown) {
      if (error instanceof SyntaxError) {
        decodedPlacement = null;
      } else {
        throw error;
      }
    }

    return {
      meetingId: row.meeting_id,
      mediaPlacement: decodedPlacement,
      ...(row.media_region === null ? {} : { mediaRegion: row.media_region }),
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    };
  }

  async upsert(context: MeetingContext): Promise<void> {
    const serializedPlacement = JSON.stringify(context.mediaPlacement);
    if (serializedPlacement === undefined) {
      throw new Error("Meeting context placement is not serializable.");
    }
    await this.database
      .prepare(
        `INSERT INTO meeting_context (
           meeting_id, media_placement_json, media_region, created_at, expires_at
         ) VALUES (?1, ?2, ?3, ?4, ?5)
         ON CONFLICT(meeting_id) DO UPDATE SET
           media_placement_json = excluded.media_placement_json,
           media_region = excluded.media_region,
           created_at = excluded.created_at,
           expires_at = excluded.expires_at`,
      )
      .bind(
        context.meetingId,
        serializedPlacement,
        context.mediaRegion ?? null,
        context.createdAt,
        context.expiresAt,
      )
      .run();
  }

  async delete(meetingId: string): Promise<void> {
    await this.database
      .prepare("DELETE FROM meeting_context WHERE meeting_id = ?1")
      .bind(meetingId)
      .run();
  }
}
