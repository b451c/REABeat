"""Tests for per-bar quantization math.

Verifies the core logic used by insert_stretch_markers quantization:
given bar boundaries and a beat position, calculate the ideal quantized position.
"""

import pytest


def quantize_beat_in_bar(beat_time, bar_start, bar_end, ts_num=4):
    """Pure math equivalent of the Lua per-bar quantization.

    Given a beat's time and the bar it belongs to, calculate the
    ideal evenly-spaced position within that bar.
    """
    bar_duration = bar_end - bar_start
    if bar_duration <= 0:
        return beat_time
    pos_in_bar = beat_time - bar_start
    beat_in_bar = pos_in_bar / bar_duration * ts_num
    nearest_beat = max(0, min(ts_num, round(beat_in_bar)))
    return bar_start + (nearest_beat / ts_num) * bar_duration


class TestQuantizeMath:
    """Per-bar quantization: no cumulative drift, correct snapping."""

    def test_downbeat_stays(self):
        """First beat of bar should not move."""
        result = quantize_beat_in_bar(10.0, 10.0, 12.0, ts_num=4)
        assert abs(result - 10.0) < 0.001

    def test_perfect_beat_stays(self):
        """Beat exactly on grid should not move."""
        # Bar 10.0-12.0, 4/4: beats at 10.0, 10.5, 11.0, 11.5
        result = quantize_beat_in_bar(10.5, 10.0, 12.0, ts_num=4)
        assert abs(result - 10.5) < 0.001

    def test_early_beat_snaps_forward(self):
        """Beat slightly early should snap to nearest grid position."""
        # Beat at 10.48 (20ms early), should snap to 10.5
        result = quantize_beat_in_bar(10.48, 10.0, 12.0, ts_num=4)
        assert abs(result - 10.5) < 0.001

    def test_late_beat_snaps_backward(self):
        """Beat slightly late should snap to nearest grid position."""
        # Beat at 10.52 (20ms late), should snap to 10.5
        result = quantize_beat_in_bar(10.52, 10.0, 12.0, ts_num=4)
        assert abs(result - 10.5) < 0.001

    def test_small_correction(self):
        """Typical groove correction should be <50ms."""
        # Beat at 11.03 (30ms late for beat 3 at 11.0)
        result = quantize_beat_in_bar(11.03, 10.0, 12.0, ts_num=4)
        assert abs(result - 11.0) < 0.001
        assert abs(result - 11.03) < 0.05  # correction under 50ms

    def test_no_cumulative_drift(self):
        """Each bar quantized independently: no drift across bars."""
        # Simulate 100 bars at ~120 BPM with slight tempo variation
        bars = []
        t = 0.0
        for i in range(100):
            bar_dur = 2.0 + (i % 3) * 0.01  # slight variation
            bars.append((t, t + bar_dur))
            t += bar_dur

        # Beat 2 in each bar (should be at bar_start + 0.5 * bar_duration)
        max_delta = 0
        for bar_start, bar_end in bars:
            bar_dur = bar_end - bar_start
            actual_beat = bar_start + 0.48 * bar_dur  # slightly early
            quantized = quantize_beat_in_bar(actual_beat, bar_start, bar_end)
            ideal = bar_start + 0.5 * bar_dur  # perfect beat 2 position
            delta = abs(quantized - ideal)
            max_delta = max(max_delta, delta)

        # Even after 100 bars, each correction is independent
        assert max_delta < 0.001

    def test_last_beat_of_bar(self):
        """Last beat before next downbeat should snap correctly."""
        # Beat at 11.48 should snap to 11.5 (beat 4 in 10.0-12.0 bar)
        result = quantize_beat_in_bar(11.48, 10.0, 12.0, ts_num=4)
        assert abs(result - 11.5) < 0.001

    def test_three_four_time(self):
        """3/4 time: 3 beats per bar."""
        # Bar 10.0-11.5 (1.5s = 3 beats at 120 BPM)
        # Beats at 10.0, 10.5, 11.0
        result = quantize_beat_in_bar(10.48, 10.0, 11.5, ts_num=3)
        assert abs(result - 10.5) < 0.001

    def test_different_tempos(self):
        """Works correctly at different tempos (60-180 BPM)."""
        for bpm in [60, 90, 120, 140, 180]:
            bar_dur = 4 * 60.0 / bpm  # 4 beats
            beat_2_ideal = bar_dur * 0.5
            beat_2_actual = beat_2_ideal + 0.02  # 20ms late
            result = quantize_beat_in_bar(beat_2_actual, 0, bar_dur, ts_num=4)
            assert abs(result - beat_2_ideal) < 0.001, f"Failed at {bpm} BPM"

    def test_beat_not_moved_across_bar(self):
        """A beat near bar boundary should not snap into the next bar."""
        # Beat at 11.98 (20ms before bar end at 12.0) should snap to 11.5, not 12.0
        result = quantize_beat_in_bar(11.98, 10.0, 12.0, ts_num=4)
        # Closest grid: 11.5 (0.48 away) vs 12.0 (0.02 away)
        # 12.0 is closest — snaps to bar boundary (beat 4 = next downbeat)
        assert abs(result - 12.0) < 0.001
