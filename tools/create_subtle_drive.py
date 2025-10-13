#!/usr/bin/env python3
"""
Create a minimal driving video with ONLY head movements.
Uses a reference face and applies small rotations/translations.
"""
import cv2
import numpy as np
import sys

def create_driving_video(image_path, output_path, duration_sec=10, fps=25):
    img = cv2.imread(image_path)
    if img is None:
        print(f"Error: Cannot load {image_path}")
        sys.exit(1)
    
    # Resize to typical LivePortrait input size
    target_h = 512
    aspect = img.shape[1] / img.shape[0]
    target_w = int(target_h * aspect)
    img = cv2.resize(img, (target_w, target_h))
    
    h, w = img.shape[:2]
    total_frames = duration_sec * fps
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(output_path, fourcc, fps, (w, h))
    
    print(f"Creating {total_frames} frames @ {fps} FPS...")
    
    for frame_idx in range(total_frames):
        t = frame_idx / fps
        
        # Very subtle movements - for FACE/HEAD, not camera!
        # Pitch (up/down): ±2° over 5s
        pitch = 2.0 * np.sin(2 * np.pi * t / 5.0)
        
        # Yaw (left/right): ±3° over 7s
        yaw = 3.0 * np.sin(2 * np.pi * t / 7.0)
        
        # Roll (tilt): ±1° over 9s  
        roll = 1.0 * np.sin(2 * np.pi * t / 9.0)
        
        # Apply transformations
        center = (w // 2, h // 2)
        
        # Rotation matrix (roll)
        M = cv2.getRotationMatrix2D(center, roll, 1.0)
        
        # Translate for pitch/yaw simulation
        tx = yaw * 2  # Convert degrees to pixels
        ty = pitch * 2
        M[0, 2] += tx
        M[1, 2] += ty
        
        frame = cv2.warpAffine(img, M, (w, h), 
                               flags=cv2.INTER_CUBIC,
                               borderMode=cv2.BORDER_REPLICATE)
        
        # Blink every 4s (darken eyes region - very rough)
        blink_t = t % 4.0
        if 0.4 < blink_t < 0.5:  # 100ms blink
            # Simple darkening (not accurate, but better than nothing)
            eye_y = int(h * 0.4)
            frame[eye_y:eye_y+20, :] = (frame[eye_y:eye_y+20, :] * 0.7).astype(np.uint8)
        
        out.write(frame)
        
        if (frame_idx + 1) % 25 == 0:
            print(f"  {frame_idx + 1}/{total_frames}")
    
    out.release()
    print(f"✅ Saved to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python create_subtle_drive.py <face_image> <output.mp4>")
        sys.exit(1)
    
    create_driving_video(sys.argv[1], sys.argv[2])

