export type VisemeEvent = { t_ms: number; weights: Record<string, number> };
export type ProsodyEvent = { t_ms: number; pitch: number; energy: number; speaking: boolean };
export type TimestampEvent = { t_ms: number; phoneme?: string|null; word?: string|null; pitch: number; energy: number };
export type SessionInfo = { id: string; avatar_id: string; voice_id: string };
