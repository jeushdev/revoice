package ai.moonshine.voice;

import java.util.List;

/** Serialized review-only policy and observable fake native boundary; NOT VAD/app code. */
public final class StopLedgerFixture {
  private enum State { ACCEPTING, STOPPED, FAILED }

  private static void check(boolean ok, String why) {
    if (!ok) throw new AssertionError(why);
  }

  private static int padding(long samples, int fedRate) {
    if (samples < 0 || fedRate != 16000) throw new IllegalArgumentException("unreviewed tally/rate");
    return (int)((512 - samples % 512) % 512);
  }

  private static final class Ledger implements AutoCloseable {
    final Transcriber sdk;
    State state = State.ACCEPTING;
    long knownSamples, knownSynthetic;
    boolean drained, uncertain;

    Ledger() {
      JNI.reset();
      sdk = new Transcriber();
      sdk.loadFromFiles("fake-local-only", JNI.MOONSHINE_MODEL_ARCH_TINY_STREAMING);
      sdk.start();
      sdk.setUpdateInterval(1000); // Scheduling fixture only; no automatic short pass.
    }

    private void active() {
      if (state != State.ACCEPTING) throw new IllegalStateException("terminal " + state);
    }

    void append(int count, boolean synthetic) {
      active();
      try {
        if (count <= 0 || (drained && !synthetic)) throw new IllegalArgumentException("invalid append");
        long next = Math.addExact(knownSamples, count);
        long nextSynthetic = synthetic ? Math.addExact(knownSynthetic, count) : knownSynthetic;
        // Public void add can fail AFTER native acceptance. No boundary hook is
        // available here: commit a known total only on success, invalidate on failure.
        sdk.addAudio(new float[count], 16000);
        knownSamples = next;
        knownSynthetic = nextSynthetic;
      } catch (RuntimeException | Error failure) {
        uncertain = true;
        state = State.FAILED;
        throw failure;
      }
    }

    void pass() {
      active();
      try { sdk.update(); }
      catch (RuntimeException | Error failure) {
        uncertain = true; state = State.FAILED; throw failure;
      }
    }

    void drain() { active(); drained = true; } // Simulates already joined/drained capture.

    void stop() {
      if (state == State.STOPPED) return; // App-owned duplicate success, no SDK replay.
      active();
      try {
        if (!drained) throw new IllegalStateException("capture not drained");
        int pad = padding(knownSamples, 16000);
        Math.addExact(knownSamples, pad); // Reject overflow BEFORE padding/native Stop.
        if (pad > 0) append(pad, true);
        sdk.stop();
        state = State.STOPPED;
      } catch (RuntimeException | Error failure) {
        uncertain = true; state = State.FAILED; throw failure;
      }
    }

    public void close() { sdk.close(); } // Fake idle cleanup only, not a successful flush.
  }

  private static void failedCall(Runnable call) {
    try { call.run(); throw new AssertionError("expected terminal failure"); }
    catch (RuntimeException | OutOfMemoryError expected) {}
  }

  private static void noReplay(Ledger l) {
    check(l.state == State.FAILED && l.uncertain, "failure did not invalidate ledger");
    int adds = JNI.addCalls, stops = JNI.stopCalls, passes = JNI.transcribeCalls;
    List<String> calls = List.copyOf(JNI.calls);
    // Even if fake error source clears, no replay/padded Stop/update is allowed.
    JNI.addStatus = JNI.stopStatus = 0;
    JNI.addThrowsOom = false;
    failedCall(() -> l.append(1, false));
    failedCall(l::pass); failedCall(l::stop); failedCall(l::stop);
    check(adds == JNI.addCalls && stops == JNI.stopCalls && passes == JNI.transcribeCalls,
        "terminal operation reentered SDK");
    check(calls.equals(JNI.calls), "terminal operation changed boundary ordering");
  }

  private static void allResidues() {
    for (int residue = 0; residue < 512; residue++) {
      try (Ledger l = new Ledger()) {
        for (int n : new int[] {1, 511, 512 + residue}) l.append(n, false);
        long total = l.knownSamples;
        int p = (512 - residue) % 512;
        int adds = JNI.addCalls, before = JNI.calls.size();
        l.drain(); l.stop();
        List<String> suffix = p == 0 ? List.of("stop", "transcribe:new")
            : List.of("add:" + p, "stop", "transcribe:new");
        check(JNI.calls.subList(before, JNI.calls.size()).equals(suffix), "pad/Stop/pass order residue " + residue);
        check(JNI.addCalls == adds + (p == 0 ? 0 : 1), "empty/missing padding");
        check(l.knownSamples == total + p && l.knownSamples % 512 == 0, "ledger alignment");
        check(JNI.addedSamples == l.knownSamples && l.knownSynthetic == p, "accepted padding tally");
        check(l.state == State.STOPPED && JNI.stopCalls == 1, "SDK Stop missing");
        List<String> completed = List.copyOf(JNI.calls);
        l.stop(); l.stop();
        check(completed.equals(JNI.calls) && JNI.stopCalls == 1, "duplicate Stop replay");
      }
    }
    try (Ledger l = new Ledger()) {
      l.drain(); l.stop();
      check(JNI.addCalls == 0 && JNI.stopCalls == 1 && !JNI.lastTranscribeHadNewAudio,
          "empty session must Stop without empty add");
    }
    try (Ledger l = new Ledger()) {
      l.append(1024, false); l.pass();
      int adds = JNI.addCalls;
      l.drain(); l.stop();
      check(JNI.addCalls == adds && JNI.stopCalls == 1 && !JNI.lastTranscribeHadNewAudio,
          "aligned no-new-audio Stop must not pad");
    }
    System.out.println("PASS SDK Stop/order for all 512 residues; P=0, empty/no-new-audio and duplicate Stop");
  }

  private static void pauseAccounting() {
    try (Ledger l = new Ledger()) {
      l.append(513, false); l.pass();
      for (int batch = 0; batch < 4; batch++) { l.append(8192, true); l.pass(); }
      check(l.knownSynthetic == 32768 && l.knownSamples == 513 + 32768, "Pause synthetic ledger");
      l.append(7, false); // Simulated resumed capture in the same stream.
      long before = l.knownSamples;
      l.drain(); l.stop();
      check(l.knownSamples == before + 504 && l.knownSynthetic == 32768 + 504, "resumed Stop tally");
      check(JNI.addedSamples == l.knownSamples && JNI.startCalls == 1 && JNI.stopCalls == 1,
          "Pause fixture dropped samples/reset stream");
    }
    System.out.println("PASS Pause synthetic/resume/Stop ledger; no claim of Pause completion");
  }

  private static void appendFailures() {
    try (Ledger l = new Ledger()) {
      JNI.addStatus = -3;
      failedCall(() -> l.append(1, false));
      check(JNI.addedSamples == 0 && l.knownSamples == 0, "rejected append counted");
      noReplay(l);
    }
    try (Ledger l = new Ledger()) {
      JNI.addThrowsOom = true;
      failedCall(() -> l.append(1, false));
      check(JNI.addedSamples == 0 && l.knownSamples == 0, "throwing fake append counted");
      noReplay(l);
    }
    try (Ledger l = new Ledger()) {
      l.sdk.setUpdateInterval(0.5); JNI.nextTranscript = null;
      failedCall(() -> l.append(8000, false));
      check(JNI.addedSamples == 8000 && l.knownSamples == 0 && JNI.transcribeCalls == 1,
          "append accepted before automatic null; known ledger must be invalidated");
      noReplay(l);
    }
    try (Ledger l = new Ledger()) {
      l.sdk.setUpdateInterval(0.5); completedFailure(l);
      failedCall(() -> l.append(8000, false));
      check(JNI.addedSamples == 8000 && l.knownSamples == 0,
          "callback failed after native acceptance; old total is NOT authoritative");
      noReplay(l);
    }
    System.out.println("PASS rejected/OOM and post-acceptance transcribe/callback failures; terminal no replay");
  }

  private static void completedFailure(Ledger l) {
    TranscriptLine line = new TranscriptLine();
    line.id = 88; line.text = "synthetic"; line.isUpdated = true; line.isComplete = true;
    Transcript result = new Transcript(); result.lines = List.of(line);
    JNI.nextTranscript = result;
    l.sdk.addListener(e -> {
      if (e instanceof TranscriptEvent.LineCompleted) throw new IllegalStateException("final fixture failure");
    });
  }

  private static void terminalStopFailuresAndOverflow() {
    for (int mode = 0; mode < 4; mode++) {
      try (Ledger l = new Ledger()) {
        l.append(1, false); l.drain();
        if (mode == 0) JNI.addStatus = -3; // Padding rejection, no native Stop.
        if (mode == 1) JNI.stopStatus = -3;
        if (mode == 2) JNI.nextTranscript = null;
        if (mode == 3) completedFailure(l);
        failedCall(l::stop);
        check(JNI.addedSamples == (mode == 0 ? 1 : 512), "padding boundary before terminal failure");
        check(JNI.stopCalls == (mode == 0 ? 0 : 1), "wrong Stop failure boundary");
        check(JNI.transcribeCalls == (mode < 2 ? 0 : 1), "failed Stop status transcribed");
        noReplay(l);
      }
    }
    try (Ledger l = new Ledger()) {
      l.append(1, false); l.sdk.setUpdateInterval(0); completedFailure(l); l.drain();
      failedCall(l::stop); // Pad accepted, but add's automatic callback fails before SDK Stop.
      check(JNI.addedSamples == 512 && l.knownSamples == 1 && JNI.stopCalls == 0,
          "failed padded append must not proceed to native Stop");
      noReplay(l);
    }
    try (Ledger l = new Ledger()) {
      failedCall(l::stop);
      check(JNI.addCalls == 0 && JNI.stopCalls == 0, "Stop before drain entered SDK");
      noReplay(l);
    }
    // Seed only the review ledger: these are virtual arithmetic boundaries,
    // not claims that the SDK processed Long.MAX_VALUE samples or timestamps.
    try (Ledger l = new Ledger()) {
      l.knownSamples = Long.MAX_VALUE - 1;
      failedCall(() -> l.append(2, false));
      check(JNI.addCalls == 0, "append overflow reached native boundary"); noReplay(l);
    }
    try (Ledger l = new Ledger()) {
      l.knownSamples = Long.MAX_VALUE; l.drain();
      failedCall(l::stop); // P=1 fits individually; N+P does not.
      check(JNI.addCalls == 0 && JNI.stopCalls == 0, "padding overflow entered SDK"); noReplay(l);
    }
    try (Ledger l = new Ledger()) {
      l.knownSamples = Long.MAX_VALUE - 511; l.drain(); l.stop();
      check(l.state == State.STOPPED && JNI.addCalls == 0 && JNI.stopCalls == 1,
          "largest aligned virtual tally should need no addition");
    }
    try (Ledger l = new Ledger()) {
      l.knownSamples = l.knownSynthetic = Long.MAX_VALUE;
      failedCall(() -> l.append(1, true));
      check(JNI.addCalls == 0, "synthetic-total overflow reached SDK"); noReplay(l);
    }
    failedCall(() -> padding(1, 48000));
    failedCall(() -> padding(-1, 16000));
    System.out.println("PASS terminal padding/Stop/snapshot/final failures, drain order and checked total/subtotal overflow");
  }

  public static void run() {
    allResidues(); pauseAccounting(); appendFailures(); terminalStopFailuresAndOverflow();
  }
}
