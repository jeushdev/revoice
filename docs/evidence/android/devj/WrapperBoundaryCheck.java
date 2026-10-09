package com.larpcode.revise.m0;

import ai.moonshine.voice.JNI;
import ai.moonshine.voice.Transcriber;
import ai.moonshine.voice.Transcript;
import ai.moonshine.voice.TranscriptEvent;
import ai.moonshine.voice.TranscriptLine;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

/** Executes the pinned Java wrapper with fake JNI. No Android/native inference. */
public final class WrapperBoundaryCheck {
    private static void check(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
    }

    private static Transcriber loaded() {
        JNI.reset();
        Transcriber t = new Transcriber();
        t.loadFromFiles("fake-local-stt", JNI.MOONSHINE_MODEL_ARCH_TINY_STREAMING);
        return t;
    }

    private static Transcript transcript(long id, boolean complete) {
        TranscriptLine line = new TranscriptLine();
        line.id = id;
        line.text = "synthetic fixture";
        line.isNew = true;
        line.isUpdated = true;
        line.hasTextChanged = true;
        line.haveSpeakersChanged = true;
        line.isComplete = complete;
        Transcript result = new Transcript();
        result.lines = List.of(line);
        return result;
    }

    private static void inlineCallbacksAndFinalDedup() {
        Transcriber t = loaded();
        List<String> events = new ArrayList<>();
        Thread caller = Thread.currentThread();
        t.addListener(event -> {
            check(Thread.currentThread() == caller, "callback must run inline");
            events.add(event.getClass().getSimpleName());
        });
        t.start();
        JNI.nextTranscript = transcript(42, true);
        t.addAudio(new float[8000], 16000);
        check(events.equals(List.of("LineStarted", "LineTextChanged",
                "LineSpeakersChanged", "LineCompleted")), "event order before add returns");
        events.clear();
        t.stop();
        check(!events.contains("LineCompleted"), "duplicate final suppressed");
        check(events.contains("LineSpeakersChanged"), "speaker revisions still delivered");
        check((JNI.lastFlags & JNI.MOONSHINE_FLAG_FORCE_UPDATE) != 0, "Stop force flag");
        t.close();
        System.out.println("PASS inline callback order, Stop force flag and final dedup");
    }

    private static void ignoredNativeStatuses() {
        Transcriber t = loaded();
        JNI.startStatus = -3;
        t.start(); // Current wrapper does not check this failure.
        JNI.addStatus = -3;
        t.addAudio(new float[1], 16000);
        JNI.stopStatus = -3;
        t.stop(); // Even a failed native stop proceeds to transcribe.
        check(JNI.startCalls == 1 && JNI.addCalls == 1 && JNI.stopCalls == 1,
                "fake failures reached all boundaries");
        check(JNI.transcribeCalls == 1, "failed Stop still transcribes");
        t.close();
        System.out.println("PASS reproduced ignored start/add/stop error statuses (SDK defect)");
    }

    private static void throttleAndFlushAttempt() {
        Transcriber t = loaded();
        t.start();
        JNI.nextTranscript = transcript(43, false);
        t.addListener(event -> {
            // Emulate a costly native pass for deterministic throttle testing.
            if (event instanceof TranscriptEvent.LineStarted) JNI.setLastPass(t, 100.0);
        });
        t.addAudio(new float[8000], 16000);
        check(JNI.transcribeCalls == 1, "default 0.5 second Java gate");
        t.addAudio(new float[8192], 16000);
        check(JNI.transcribeCalls == 1, "0.512 second silence hidden by stretched Java gate");
        t.setUpdateInterval(0.0);
        t.addAudio(new float[8192], 16000);
        check(JNI.transcribeCalls == 2, "temporary Java gate bypass asks for a pass");
        // Fake native still reports incomplete: a forced request is NOT finalization.
        check(!JNI.nextTranscript.lines.get(0).isComplete, "request alone is not a final");
        t.setUpdateInterval(0.5);
        t.close();
        System.out.println("PASS throttle risk and gate bypass; no native VAD finalization claimed");
    }

    private static void stopNullAndListenerFailure() {
        Transcriber t = loaded();
        JNI.nextTranscript = null;
        try {
            t.stop();
            throw new AssertionError("null Stop transcript was not rejected");
        } catch (NullPointerException expected) {
            // Evidence of the missing explicit null guard, not desired app behavior.
        }
        t.close();

        t = loaded();
        t.setUpdateInterval(0.0);
        JNI.nextTranscript = transcript(44, true);
        AtomicInteger finals = new AtomicInteger();
        t.addListener(event -> {
            if (event instanceof TranscriptEvent.LineCompleted) {
                finals.incrementAndGet();
                throw new IllegalStateException("synthetic listener failure");
            }
        });
        try {
            t.addAudio(new float[8000], 16000);
            throw new AssertionError("listener exception did not propagate");
        } catch (IllegalStateException expected) {
            check("synthetic listener failure".equals(expected.getMessage()), "listener failure");
        }
        t.addAudio(new float[8000], 16000);
        check(finals.get() == 1, "wrapper marks completed before listener; no redelivery");
        t.close();
        System.out.println("PASS null Stop transcript and non-retried failed final listener reproduced");
    }

    public static void main(String[] args) {
        inlineCallbacksAndFinalDedup();
        ignoredNativeStatuses();
        throttleAndFlushAttempt();
        stopNullAndListenerFailure();
    }
}
