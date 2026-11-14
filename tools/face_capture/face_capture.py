"""Local (desktop) webcam face capture for the player sprite.

Started by face_swap.gd when the game runs outside the browser. Mirrors web/face_capture.js:
the default face (oblicej.png) gives the target layout and the alpha mask; every --interval
seconds one webcam frame is checked; the first usable frontal face is aligned (eyes + mouth)
onto the default layout, cut with the default mask and written as PNG. Then it exits.

Exit codes: 0 = face written, 1 = game or launcher gone, 2 = camera/model problem.
Runs until a face is found, the game (--parent-pid) exits, or it is killed.
"""

import argparse
import math
import os
import sys
import time

import cv2
import numpy as np

MIN_SCORE = 0.85
MIN_FACE_WIDTH = 0.15  # fraction of the frame width
MAX_ROLL_DEG = 15.0

# Used when the detector can't find the face in oblicej.png itself (pixels, 802x1382).
FALLBACK_TARGET = np.float32([[173, 478], [590, 504], [354, 973]])


def make_detector(model: str, w: int, h: int):
    return cv2.FaceDetectorYN.create(model, "", (w, h), score_threshold=0.6)


def points(face) -> np.ndarray:
    """YuNet row -> [eye_right, eye_left, mouth_center] (image coords)."""
    lm = face[4:14].reshape(5, 2)
    mouth = (lm[3] + lm[4]) / 2.0
    return np.float32([lm[0], lm[1], mouth])


def target_points(model: str, mask_bgra: np.ndarray) -> np.ndarray:
    h, w = mask_bgra.shape[:2]
    pad = max(w, h)
    bg = np.full((h + 2 * pad, w + 2 * pad, 3), 128, np.uint8)
    alpha = mask_bgra[:, :, 3:4].astype(np.float32) / 255.0
    face = mask_bgra[:, :, :3].astype(np.float32) * alpha + 128 * (1 - alpha)
    bg[pad:pad + h, pad:pad + w] = face.astype(np.uint8)
    # Downscale so the detector works at a sane size.
    scale = 640.0 / bg.shape[1]
    small = cv2.resize(bg, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    det = make_detector(model, small.shape[1], small.shape[0])
    _, faces = det.detect(small)
    if faces is None or len(faces) == 0:
        print("face_capture: default face not detected, using fallback points", file=sys.stderr)
        return FALLBACK_TARGET
    best = max(faces, key=lambda f: f[14])
    return points(best) / scale - pad


def usable(face, frame_w: int):
    if face[14] < MIN_SCORE or face[2] / frame_w < MIN_FACE_WIDTH:
        return None
    lm = face[4:14].reshape(5, 2)
    eye_a, eye_b, nose = lm[0], lm[1], lm[2]
    roll = abs(math.degrees(math.atan2(eye_b[1] - eye_a[1], eye_b[0] - eye_a[0])))
    if min(roll, 180 - roll) > MAX_ROLL_DEG:
        return None
    if not (min(eye_a[0], eye_b[0]) <= nose[0] <= max(eye_a[0], eye_b[0])):
        return None
    return points(face)


def cut_face(frame: np.ndarray, src: np.ndarray, dst: np.ndarray, mask_bgra: np.ndarray) -> np.ndarray:
    h, w = mask_bgra.shape[:2]
    m, _ = cv2.estimateAffinePartial2D(src, dst, method=cv2.LMEDS)
    warped = cv2.warpAffine(frame, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    out = cv2.cvtColor(warped, cv2.COLOR_BGR2BGRA)
    out[:, :, 3] = mask_bgra[:, :, 3]
    return out


def alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--mask", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--interval", type=float, default=3.0)
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--parent-pid", type=int, default=0, help="exit when this process (the game) is gone")
    args = ap.parse_args()

    mask = cv2.imread(args.mask, cv2.IMREAD_UNCHANGED)
    if mask is None or mask.ndim != 3 or mask.shape[2] != 4:
        print(f"face_capture: bad mask {args.mask}", file=sys.stderr)
        return 2
    target = target_points(args.model, mask)

    cap = cv2.VideoCapture(args.camera, cv2.CAP_V4L2)
    if not cap.isOpened():
        print("face_capture: camera not available", file=sys.stderr)
        return 2
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    launcher = os.getppid()
    detector = None
    try:
        while True:
            # Read continuously so the frame we check is fresh, check every --interval s.
            deadline = time.monotonic() + args.interval
            ok, frame = cap.read()
            while time.monotonic() < deadline:
                ok, frame = cap.read()
                if args.parent_pid and not alive(args.parent_pid):
                    return 1
                if os.getppid() != launcher:  # `uv run` was killed (game went back to menu)
                    return 1
            if not ok or frame is None:
                continue
            fh, fw = frame.shape[:2]
            if detector is None:
                detector = make_detector(args.model, fw, fh)
            _, faces = detector.detect(frame)
            if faces is None or len(faces) == 0:
                continue
            src = usable(max(faces, key=lambda f: f[14]), fw)
            if src is None:
                continue
            face = cut_face(frame, src, target, mask)
            tmp = args.out + ".tmp.png"
            cv2.imwrite(tmp, face)
            os.replace(tmp, args.out)
            return 0
    finally:
        cap.release()


if __name__ == "__main__":
    sys.exit(main())
