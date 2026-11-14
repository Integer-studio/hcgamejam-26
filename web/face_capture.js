// Face capture for the web build.
// Loaded by face_swap.gd via JavaScriptBridge.eval(). Exposes window.faceCapture.start().
//
// Flow: the default face (oblicej.png) gives the target layout and the alpha mask.
// Every 3 s one frame from the webcam is checked; when a usable frontal face is found,
// it is aligned (eyes + mouth) onto the default layout, cut with the default mask and
// handed back to Godot as a PNG data URL. Camera is stopped afterwards.
// Everything stays in the browser, nothing is uploaded.
(function () {
	"use strict";

	const VISION_VERSION = "0.10.14";
	const VISION_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VISION_VERSION}/vision_bundle.mjs`;
	const WASM_URL = `https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@${VISION_VERSION}/wasm`;
	const MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite";

	const INTERVAL_MS = 3000;
	const MIN_SCORE = 0.85;
	const MIN_FACE_WIDTH = 0.15;      // fraction of the video width
	const MAX_ROLL_DEG = 15;

	// Keypoint indices of MediaPipe FaceDetector.
	const EYE_A = 0, EYE_B = 1, NOSE = 2, MOUTH = 3;

	// Used when the detector can't find the face in oblicej.png itself (pixels, 802x1382).
	const FALLBACK_TARGET = [[173, 478], [590, 504], [354, 973]];

	let started = false;

	function loadImage(src) {
		return new Promise((resolve, reject) => {
			const img = new Image();
			img.onload = () => resolve(img);
			img.onerror = reject;
			img.src = src;
		});
	}

	// Detect the default face to get its eye/mouth positions. The face fills the whole
	// image, which the short-range model handles badly, so it is padded first.
	function targetPoints(detector, img) {
		const pad = Math.max(img.width, img.height);
		const c = document.createElement("canvas");
		c.width = img.width + pad * 2;
		c.height = img.height + pad * 2;
		const ctx = c.getContext("2d");
		ctx.fillStyle = "#808080";
		ctx.fillRect(0, 0, c.width, c.height);
		ctx.drawImage(img, pad, pad);
		const res = detector.detect(c);
		const det = res.detections && res.detections[0];
		if (!det) {
			console.warn("faceCapture: default face not detected, using fallback points");
			return FALLBACK_TARGET;
		}
		const kp = det.keypoints;
		return [EYE_A, EYE_B, MOUTH].map((i) => [kp[i].x * c.width - pad, kp[i].y * c.height - pad]);
	}

	// Returns [[x,y] eyeA, eyeB, mouth] in video pixels, or null when the face is unusable.
	function usableFace(det, w, h) {
		if (!det) return null;
		const score = det.categories && det.categories[0] ? det.categories[0].score : 0;
		if (score < MIN_SCORE) return null;
		if (det.boundingBox.width / w < MIN_FACE_WIDTH) return null;
		const kp = det.keypoints;
		const p = (i) => [kp[i].x * w, kp[i].y * h];
		const a = p(EYE_A), b = p(EYE_B), nose = p(NOSE), mouth = p(MOUTH);
		const roll = Math.abs(Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math.PI);
		if (Math.min(roll, 180 - roll) > MAX_ROLL_DEG) return null;
		// Frontal: nose horizontally between the eyes.
		if (nose[0] < Math.min(a[0], b[0]) || nose[0] > Math.max(a[0], b[0])) return null;
		return [a, b, mouth];
	}

	// Least-squares similarity transform (rotation + uniform scale + translation) src -> dst.
	// Returns canvas setTransform args: x' = a*x - b*y + tx, y' = b*x + a*y + ty.
	function similarity(src, dst) {
		const n = src.length;
		let sx = 0, sy = 0, dx = 0, dy = 0;
		for (let i = 0; i < n; i++) { sx += src[i][0]; sy += src[i][1]; dx += dst[i][0]; dy += dst[i][1]; }
		sx /= n; sy /= n; dx /= n; dy /= n;
		let num_a = 0, num_b = 0, den = 0;
		for (let i = 0; i < n; i++) {
			const px = src[i][0] - sx, py = src[i][1] - sy;
			const qx = dst[i][0] - dx, qy = dst[i][1] - dy;
			num_a += px * qx + py * qy;
			num_b += px * qy - py * qx;
			den += px * px + py * py;
		}
		const a = num_a / den, b = num_b / den;
		const tx = dx - (a * sx - b * sy);
		const ty = dy - (b * sx + a * sy);
		return [a, b, -b, a, tx, ty];
	}

	function cutFace(video, src, dst, mask) {
		const c = document.createElement("canvas");
		c.width = mask.width;
		c.height = mask.height;
		const ctx = c.getContext("2d");
		ctx.setTransform(...similarity(src, dst));
		ctx.drawImage(video, 0, 0);
		ctx.setTransform(1, 0, 0, 1, 0, 0);
		ctx.globalCompositeOperation = "destination-in";
		ctx.drawImage(mask, 0, 0);
		return c.toDataURL("image/png");
	}

	async function run(defaultPngBase64, onFound) {
		const vision = await import(VISION_URL);
		const fileset = await vision.FilesetResolver.forVisionTasks(WASM_URL);
		const detector = await vision.FaceDetector.createFromOptions(fileset, {
			baseOptions: { modelAssetPath: MODEL_URL },
			runningMode: "IMAGE",
		});

		const mask = await loadImage("data:image/png;base64," + defaultPngBase64);
		const target = targetPoints(detector, mask);

		const stream = await navigator.mediaDevices.getUserMedia({
			video: { width: { ideal: 1280 }, height: { ideal: 720 } },
			audio: false,
		});
		const video = document.createElement("video");
		video.muted = true;
		video.playsInline = true;
		video.srcObject = stream;
		await video.play();

		const stop = (timer) => {
			clearInterval(timer);
			stream.getTracks().forEach((t) => t.stop());
			detector.close();
		};

		const timer = setInterval(() => {
			if (video.readyState < 2) return;
			const w = video.videoWidth, h = video.videoHeight;
			const res = detector.detect(video);
			const src = usableFace(res.detections && res.detections[0], w, h);
			if (!src) return;
			const dataUrl = cutFace(video, src, target, mask);
			stop(timer);
			onFound(dataUrl);
		}, INTERVAL_MS);
	}

	window.faceCapture = {
		start(defaultPngBase64, onFound) {
			if (started) return;
			started = true;
			run(defaultPngBase64, onFound).catch((e) => console.warn("faceCapture:", e));
		},
	};
})();
