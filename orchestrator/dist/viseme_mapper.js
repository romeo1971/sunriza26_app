/**
 * Phoneme -> Viseme mapping + coarticulation + critically damped smoothing.
 */
const MAP = {
    "AA": "AI", "AE": "AI", "AH": "AI", "AO": "O", "OW": "O", "UH": "U", "UW": "U",
    "P": "MBP", "B": "MBP", "M": "MBP", "F": "FV", "V": "FV", "L": "L", "W": "WQ", "R": "R",
    "CH": "CH", "JH": "CH", "TH": "TH", "DH": "TH", "EH": "E", "IY": "E", "IH": "E"
};
export class VisemeMapper {
    last = {};
    lastT = 0;
    consumeTimestamp(ts) {
        const t = ts.t_ms;
        this.lastT = t;
        const weights = {};
        if (ts.phoneme) {
            const v = MAP[ts.phoneme] || "Rest";
            weights[v] = (weights[v] ?? 0) + 1;
        }
        if (!Object.keys(weights).length)
            return null;
        // normalize
        let s = 0;
        for (const k in weights)
            s += weights[k];
        for (const k in weights)
            weights[k] = weights[k] / s;
        // coarticulation: smear into neighbors
        const kDecay = 0.85;
        for (const k in this.last) {
            weights[k] = Math.max(weights[k] ?? 0, this.last[k] * kDecay);
        }
        // critically-damped smoothing towards new weights
        const dt = 16.7; // assume ~60fps step
        const wn = 14.0; // tune as needed
        const alpha = 1 - Math.exp(-wn * dt / 1000);
        const smoothed = {};
        for (const k of new Set([...Object.keys(this.last), ...Object.keys(weights)])) {
            const prev = this.last[k] ?? 0;
            const target = weights[k] ?? 0;
            smoothed[k] = prev + alpha * (target - prev);
        }
        this.last = smoothed;
        return { t_ms: t, weights: smoothed };
    }
}
