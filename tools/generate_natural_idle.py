#!/usr/bin/env python3
"""
Generate a natural-looking idle video with subtle movements:
- Head tilt (±1-2°)
- Breathing motion (vertical)
- Slight zoom (0.5%)
- Blink simulation
"""
import cv2
import numpy as np
import sys

def generate_idle_video(image_path, output_path, duration_sec=10, fps=30):
    # Load image
    img = cv2.imread(image_path)
    if img is None:
        print(f"Error: Cannot load image {image_path}")
        sys.exit(1)
    
    h, w = img.shape[:2]
    total_frames = duration_sec * fps
    
    # Video writer
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (w, h))
    
    print(f"Generating {total_frames} frames @ {fps} FPS...")
    
    for frame_idx in range(total_frames):
        t = frame_idx / fps  # Time in seconds
        
        # 1. Breathing: Slow vertical movement (4s cycle)
        breathing_y = np.sin(2 * np.pi * t / 4.0) * 8  # ±8 pixels (sichtbar!)
        
        # 2. Head sway: Slow horizontal movement (6s cycle)
        sway_x = np.sin(2 * np.pi * t / 6.0) * 6  # ±6 pixels (sichtbar!)
        
        # 3. Subtle zoom: 1.5% variance (8s cycle)
        zoom = 1.0 + 0.015 * np.sin(2 * np.pi * t / 8.0)
        
        # 4. Tiny rotation: ±1.5° (10s cycle)
        angle = 1.5 * np.sin(2 * np.pi * t / 10.0)
        
        # Create transformation matrix
        center = (w // 2, h // 2)
        M_rotate = cv2.getRotationMatrix2D(center, angle, zoom)
        M_rotate[0, 2] += sway_x
        M_rotate[1, 2] += breathing_y
        
        # Apply transformation
        frame = cv2.warpAffine(img, M_rotate, (w, h), 
                               flags=cv2.INTER_CUBIC,
                               borderMode=cv2.BORDER_REPLICATE)
        
        # 5. Blink simulation (every 3-5 seconds, very subtle darkening of eye region)
        # For simplicity, we'll add a global subtle brightness variation
        blink_cycle = 3.5  # seconds
        blink_phase = (t % blink_cycle) / blink_cycle
        if 0.45 < blink_phase < 0.55:  # 10% of cycle = quick blink
            blink_alpha = 1.0 - 0.15 * np.sin((blink_phase - 0.45) * 10 * np.pi)
            frame = (frame * blink_alpha).astype(np.uint8)
        
        out.write(frame)
        
        if (frame_idx + 1) % 30 == 0:
            print(f"  Progress: {frame_idx + 1}/{total_frames} frames")
    
    out.release()
    print(f"✅ Video saved to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python generate_natural_idle.py <input_image> <output_video>")
        sys.exit(1)
    
    generate_idle_video(sys.argv[1], sys.argv[2], duration_sec=10, fps=30)

