package ai.moonshine.voice;

import java.lang.reflect.Field;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

/** Review-only fake JNI tests; NOT Android, inference or production policy. */
public final class CheckedBoundaryTest {
  private static void check(boolean ok, String why) {
    if (!ok) throw new AssertionError(why);
  }

  @SuppressWarnings("unchecked")
  private static Map<Integer, Double> pending(Transcriber t) throws Exception {
    Field f = Transcriber.class.getDeclaredField("pendingSeconds");
    f.setAccessible(true); // Test introspection only; no production reflection.
    return (Map<Integer, Double>) f.get(t);
  }

  private static Transcriber loaded() {
    JNI.reset();
    Transcriber t = new Transcriber();
    t.loadFromFiles("fake-local-only", JNI.MOONSHINE_MODEL_ARCH_TINY_STREAMING);
    t.start();
    return t;
  }

  private static void fails(Runnable call, String expected) {
    try {
      call.run();
      throw new AssertionError("Expected failure: " + expected);
    } catch (RuntimeException e) {
      check(e.getMessage().contains(expected), "wrong error: " + e);
    }
  }

  private static void statuses() throws Exception {
    for (int status : new int[] {-1, -2, -3, -4, 7}) {
      Transcriber t = loaded();
      AtomicInteger events = new AtomicInteger();
      t.addListener(e -> events.incrementAndGet());
      t.addAudio(new float[4000], 16000);
      t.lastPassSeconds.put(1, 0.75);
      JNI.startStatus = status;
      fails(t::start, "start stream: " + status);
      check(pending(t).get(1) == 0.25, "failed start reset pending");
      check(t.lastPassSeconds.get(1) == 0.75, "failed start reset cost");
      JNI.addStatus = status;
      fails(() -> t.addAudio(new float[8000], 16000), "add audio to stream: " + status);
      check(pending(t).get(1) == 0.25, "failed add counted samples");
      check(JNI.transcribeCalls == 0 && events.get() == 0, "phantom failed-add pass");
      JNI.stopStatus = status;
      fails(t::stop, "stop stream: " + status);
      check(pending(t).get(1) == 0.25, "failed stop reset pending");
      check(JNI.transcribeCalls == 0 && events.get() == 0, "phantom failed-stop final");
      t.close();
    }
    System.out.println("PASS five native statuses propagate without phantom counts/callbacks");
  }

  private static void validationAndOom() throws Exception {
    Transcriber t = loaded();
    fails(() -> t.addAudio(null, 16000), "Audio must");
    fails(() -> t.addAudio(new float[0], 16000), "Audio must");
    fails(() -> t.addAudio(new float[1], 0), "Audio must");
    check(JNI.addCalls == 0, "invalid arguments reached JNI");
    t.addAudio(new float[4000], 16000);
    JNI.addThrowsOom = true;
    try {
      t.addAudio(new float[8000], 16000);
      throw new AssertionError("OOM swallowed");
    } catch (OutOfMemoryError expected) {
      check(pending(t).get(1) == 0.25 && JNI.transcribeCalls == 0, "OOM changed counters");
    }
    t.close();
    System.out.println("PASS invalid audio rejected; pending JNI OOM propagates");
  }

  private static void nullAndListenerFailure() throws Exception {
    Transcriber t = loaded();
    t.addAudio(new float[4000], 16000);
    JNI.nextTranscript = null;
    fails(t::stop, "stopped stream");
    check(pending(t).get(1) == 0.25, "null Stop changed counters");
    fails(t::update, "update stream");
    check(pending(t).get(1) == 0.25, "null update changed counters");
    t.close();
    t = loaded();
    TranscriptLine line = new TranscriptLine();
    line.id = 33; line.text = "synthetic"; line.isUpdated = true; line.isComplete = true;
    Transcript result = new Transcript(); result.lines = List.of(line);
    JNI.nextTranscript = result;
    t.addListener(e -> { throw new IllegalStateException("listener failure"); });
    fails(t::update, "listener failure");
    t.close();
    System.out.println("PASS null Stop/update and listener failures propagate");
  }

  private static void automaticNullAndFinalNonRedelivery() throws Exception {
    Transcriber t = loaded();
    AtomicInteger events = new AtomicInteger();
    t.addListener(e -> events.incrementAndGet());
    t.lastPassSeconds.put(1, Double.NEGATIVE_INFINITY); // Deterministic old-cost sentinel.
    t.addAudio(new float[4000], 16000);
    check(pending(t).get(1) == 0.25 && JNI.transcribeCalls == 0, "initial cadence");
    JNI.nextTranscript = null;
    final Transcriber automatic = t;
    fails(() -> automatic.addAudio(new float[4000], 16000), "Failed to transcribe stream");
    check(JNI.addedSamples == 8000 && JNI.transcribeCalls == 1, "null after successful native add");
    check(pending(t).get(1) == 0.0, "inherited due-add clears cadence before null");
    double cost = t.lastPassSeconds.get(1);
    check(Double.isFinite(cost) && cost >= 0, "inherited due-add overwrites cost before null");
    check(events.get() == 0, "null automatic pass emitted callbacks");
    t.close(); // Terminal disposition, NOT audio replay based on cadence=0.

    t = loaded();
    TranscriptLine line = new TranscriptLine();
    line.id = 55; line.text = "synthetic final"; line.isNew = true;
    line.isUpdated = true; line.hasTextChanged = true; line.isComplete = true;
    Transcript result = new Transcript(); result.lines = List.of(line);
    JNI.nextTranscript = result;
    AtomicInteger firstFinal = new AtomicInteger();
    AtomicInteger laterFinal = new AtomicInteger();
    java.util.List<String> order = new java.util.ArrayList<>();
    t.addListener(e -> {
      order.add(e.getClass().getSimpleName());
      if (e instanceof TranscriptEvent.LineCompleted) {
        firstFinal.incrementAndGet();
        throw new IllegalStateException("exact completed listener failure");
      }
    });
    t.addListener(e -> { if (e instanceof TranscriptEvent.LineCompleted) laterFinal.incrementAndGet(); });
    final Transcriber current = t;
    fails(() -> current.addAudio(new float[8000], 16000), "exact completed listener failure");
    check(order.equals(List.of("LineStarted", "LineTextChanged", "LineCompleted")), "exact final throw order");
    check(firstFinal.get() == 1 && laterFinal.get() == 0, "later listener should miss failed final");
    // Isolated SDK regression observation only, NOT permitted session recovery.
    t.update();
    check(firstFinal.get() == 1 && laterFinal.get() == 0, "completed ID was recorded; no final redelivery");
    check(JNI.addCalls == 1 && JNI.addedSamples == 8000, "regression probe replayed audio");
    t.close();
    System.out.println("PASS exact due-add null cadence mutation and LineCompleted non-redelivery regression");
  }

  private static void explicitPass() throws Exception {
    Transcriber t = loaded();
    t.lastPassSeconds.put(1, 100.0);
    TranscriptLine line = new TranscriptLine();
    line.id = 44; line.text = "still partial"; line.isNew = true;
    Transcript partial = new Transcript(); partial.lines = List.of(line);
    JNI.nextTranscript = partial;
    AtomicInteger finals = new AtomicInteger();
    t.addListener(e -> { if (e instanceof TranscriptEvent.LineCompleted) finals.incrementAndGet(); });
    t.addAudio(new float[8192], 16000);
    check(JNI.transcribeCalls == 0, "fixture should hit stretched Java gate");
    t.update();
    check(JNI.transcribeCalls == 1 && (JNI.lastFlags & 1) != 0, "explicit force pass missing");
    check(JNI.stopCalls == 0 && JNI.startCalls == 1, "explicit update reset stream");
    check(t.getUpdateInterval() == 0.5 && pending(t).get(1) == 0, "update altered interval");
    check(finals.get() == 0, "forced update invented completion");
    t.close();
    System.out.println("PASS explicit update bypasses gate without inventing a final/reset");
  }

  private static void tailAndPauseBudget() {
    Transcriber t = loaded();
    t.setUpdateInterval(1000);
    // Trial cap only: an empty transcript is deliberately NOT completion proof.
    for (int batch = 0; batch < 4; batch++) {
      t.addAudio(new float[8192], 16000);
      t.update();
    }
    check(JNI.addedSamples == 32768 && JNI.transcribeCalls == 4, "Pause budget/scheduling");
    check(JNI.stopCalls == 0 && JNI.startCalls == 1, "Pause trial reset stream");
    t.close();
    System.out.println("PASS bounded four-pass Pause scheduling fixture (not completion proof)");
  }

  public static void main(String[] args) throws Exception {
    statuses(); validationAndOom(); nullAndListenerFailure(); automaticNullAndFinalNonRedelivery();
    explicitPass(); tailAndPauseBudget(); StopLedgerFixture.run();
    System.out.println("No native inference, microphone, Android runtime or device exercised.");
  }
}
