#!/usr/bin/env python3
"""Create a natural driving video with simple, realistic movements."""
import cv2
import numpy as np
import sys

def create_natural_driver(base_face_path, output_path, duration_sec=10, fps=25):
    """
    Create a natural driving video with:
    - Light mouth open/close
    - Subtle smile
    - Natural blinks
    - Gentle head movements
    """
    img = cv2.imread(base_face_path)
    if img is None:
        print(f"Error: Cannot load {base_face_path}")
        return
    
    # Resize to 512x512
    img = cv2.resize(img, (512, 512))
    h, w = img.shape[:2]
    
    num_frames = duration_sec * fps
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (w, h))
    
    print(f"Creating {num_frames} frames @ {fps} FPS...")
    
    # Define ROIs (approximations)
    mouth_y = int(h * 0.68)
    mouth_h = int(h * 0.12)
    eye_y = int(h * 0.40)
    eye_h = int(h * 0.08)
    
    for frame_idx in range(num_frames):
        t = frame_idx / fps
        
        # Copy base image
        frame = img.copy()
        
        # 1. GENTLE HEAD MOVEMENTS (very subtle)
        yaw = 1.5 * np.sin(2 * np.pi * t / 7.0)  # ±1.5° over 7s
        pitch = 0.8 * np.sin(2 * np.pi * t / 5.0)  # ±0.8° over 5s
        roll = 0.4 * np.sin(2 * np.pi * t / 9.0)  # ±0.4° over 9s
        
        center = (w // 2, h // 2)
        M = cv2.getRotationMatrix2D(center, roll, 1.0)
        M[0, 2] += yaw * 3  # pixels
        M[1, 2] += pitch * 3
        
        frame = cv2.warpAffine(frame, M, (w, h), 
                               flags=cv2.INTER_CUBIC,
                               borderMode=cv2.BORDER_REPLICATE)
        
        # 2. MOUTH MOVEMENT (open/close + smile)
        # Mouth opens slightly every 4 seconds
        mouth_cycle = t % 4.0
        if 0.5 < mouth_cycle < 2.5:  # Open phase
            mouth_open = 0.3 * np.sin(np.pi * (mouth_cycle - 0.5) / 2.0)
            # Darken mouth area slightly (simulate opening)
            mouth_region = frame[mouth_y:mouth_y+mouth_h, :]
            frame[mouth_y:mouth_y+mouth_h, :] = (mouth_region * (1 - mouth_open * 0.2)).astype(np.uint8)
        
        # Subtle smile (lip corners up)
        smile_phase = t % 6.0
        if 1.0 < smile_phase < 3.0:  # Smile for 2s every 6s
            smile_amt = 0.5 * np.sin(np.pi * (smile_phase - 1.0) / 2.0)
            # Slight brightening at mouth corners (crude but works)
            corners = [
                (int(w * 0.35), mouth_y + mouth_h // 2),
                (int(w * 0.65), mouth_y + mouth_h // 2)
            ]
            for cx, cy in corners:
                cv2.circle(frame, (cx, cy), 8, 
                          tuple((int(c * (1 + smile_amt * 0.1)) for c in [255, 255, 255])), 
                          -1, cv2.LINE_AA)
        
        # 3. NATURAL BLINKS (every 3-5 seconds)
        blink_times = [1.5, 4.8, 8.2]  # Natural intervals
        for t_blink in blink_times:
            if abs(t - t_blink) < 0.15:  # 300ms blink
                blink_progress = (t - (t_blink - 0.075)) / 0.15
                if blink_progress < 0.5:
                    # Closing
                    blink_amt = blink_progress * 2
                else:
                    # Opening
                    blink_amt = (1 - blink_progress) * 2
                
                # Darken eye region
                eye_region = frame[eye_y:eye_y+eye_h, :]
                frame[eye_y:eye_y+eye_h, :] = (eye_region * (1 - blink_amt * 0.6)).astype(np.uint8)
        
        out.write(frame)
        
        if (frame_idx + 1) % 25 == 0:
            print(f"  {frame_idx + 1}/{num_frames}")
    
    out.release()
    print(f"✅ Saved to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python create_natural_driver.py <face_image> <output.mp4>")
        sys.exit(1)
    
    create_natural_driver(sys.argv[1], sys.argv[2])

