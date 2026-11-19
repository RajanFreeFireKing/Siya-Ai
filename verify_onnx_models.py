#!/usr/bin/env python3
"""
Verification Script for Siya AI Audio & Emotion Detection Models:
1. Silero VAD v5 (silero_vad.onnx)
2. AST Audio Classifier (ast_int8.onnx)
3. Emotion2Vec Plus Distilled (emotion2vec_int8.onnx)
"""

import os
import sys
import json
import numpy as np
import onnxruntime as ort

ASSETS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "android/app/src/main/assets")

def test_silero_vad():
    vad_path = os.path.join(ASSETS_DIR, "silero_vad.onnx")
    print(f"\n[1/3] Testing Silero VAD v5 ({os.path.basename(vad_path)})...")
    assert os.path.exists(vad_path), f"File not found: {vad_path}"
    
    session = ort.InferenceSession(vad_path, providers=['CPUExecutionProvider'])
    
    # 512 samples at 16kHz = 32ms frame
    dummy_audio = np.random.uniform(-0.1, 0.1, (1, 512)).astype(np.float32)
    state = np.zeros((2, 1, 128), dtype=np.float32)
    sr = np.array(16000, dtype=np.int64)
    
    outputs = session.run(None, {'input': dummy_audio, 'state': state, 'sr': sr})
    vad_prob = float(outputs[0][0][0])
    new_state = outputs[1]
    
    print(f"  ✓ Session initialized successfully.")
    print(f"  ✓ Input shape: {dummy_audio.shape}, Sample Rate: 16000")
    print(f"  ✓ Speech probability: {vad_prob:.4f}")
    print(f"  ✓ Updated state tensor shape: {new_state.shape}")
    print("  -> Silero VAD v5 Verification: PASSED ✅")
    return True

def test_ast_classifier():
    ast_path = os.path.join(ASSETS_DIR, "ast_int8.onnx")
    labels_path = os.path.join(ASSETS_DIR, "ast_labels.json")
    print(f"\n[2/3] Testing AST Audio Classifier ({os.path.basename(ast_path)})...")
    assert os.path.exists(ast_path), f"File not found: {ast_path}"
    
    labels = {}
    if os.path.exists(labels_path):
        with open(labels_path, "r") as f:
            labels = json.load(f)
            
    session = ort.InferenceSession(ast_path, providers=['CPUExecutionProvider'])
    
    # AST accepts input_values of shape [batch_size, 1024, 128]
    dummy_features = np.random.randn(1, 1024, 128).astype(np.float32) * 0.1
    input_name = session.get_inputs()[0].name
    outputs = session.run(None, {input_name: dummy_features})
    logits = outputs[0][0]
    
    # Softmax
    exp_logits = np.exp(logits - np.max(logits))
    probs = exp_logits / np.sum(exp_logits)
    
    top5_indices = np.argsort(probs)[::-1][:5]
    print(f"  ✓ Session initialized successfully.")
    print(f"  ✓ Input feature shape: {dummy_features.shape}")
    print(f"  ✓ Logits output count: {len(logits)} classes")
    print("  ✓ Top detected audio events:")
    for rank, idx in enumerate(top5_indices, 1):
        label_name = labels.get(str(idx), f"Class_{idx}")
        print(f"     {rank}. {label_name} (Class {idx}): {probs[idx]:.4f}")
        
    print("  -> AST Audio Classifier Verification: PASSED ✅")
    return True

def test_emotion2vec():
    e2v_path = os.path.join(ASSETS_DIR, "emotion2vec_int8.onnx")
    labels_path = os.path.join(ASSETS_DIR, "emotion_labels.json")
    print(f"\n[3/3] Testing Emotion2Vec Plus ({os.path.basename(e2v_path)})...")
    assert os.path.exists(e2v_path), f"File not found: {e2v_path}"
    
    labels = []
    if os.path.exists(labels_path):
        with open(labels_path, "r") as f:
            labels = json.load(f)
            
    session = ort.InferenceSession(e2v_path, providers=['CPUExecutionProvider'])
    input_name = session.get_inputs()[0].name
    
    # 48000 samples = 3 seconds at 16kHz
    dummy_waveform = np.random.uniform(-0.2, 0.2, (1, 48000)).astype(np.float32)
    outputs = session.run(None, {input_name: dummy_waveform})
    scores = outputs[0][0]
    
    # Softmax temperature calibrated
    exp_scores = np.exp((scores - np.max(scores)) / 0.0375)
    probs = exp_scores / np.sum(exp_scores)
    
    top3_indices = np.argsort(probs)[::-1][:3]
    print(f"  ✓ Session initialized successfully.")
    print(f"  ✓ Input waveform shape: {dummy_waveform.shape} (3s @ 16kHz)")
    print(f"  ✓ Output score vector dimension: {len(scores)}")
    print("  ✓ Top detected emotional states:")
    for rank, idx in enumerate(top3_indices, 1):
        label_name = labels[idx] if idx < len(labels) else f"Emotion_{idx}"
        print(f"     {rank}. {label_name}: score={scores[idx]:.4f}, prob={probs[idx]:.4f}")
        
    print("  -> Emotion2Vec Plus Verification: PASSED ✅")
    return True

def main():
    print("=" * 60)
    print("  SIYA AI ONNX MODELS VERIFICATION TEST")
    print("=" * 60)
    try:
        vad_ok = test_silero_vad()
        ast_ok = test_ast_classifier()
        e2v_ok = test_emotion2vec()
        
        print("\n" + "=" * 60)
        if vad_ok and ast_ok and e2v_ok:
            print("  ALL 3 ONNX MODELS VERIFIED & FUNCTIONAL! 🎉")
            print("=" * 60)
            return 0
        else:
            print("  VERIFICATION FAILED! ❌")
            print("=" * 60)
            return 1
    except Exception as e:
        print(f"\n❌ Error during verification: {e}")
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    sys.exit(main())
