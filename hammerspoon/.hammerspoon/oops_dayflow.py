"""oops_dayflow.py — fill an Oops incident's screens/ from Dayflow's recording.

Requested 2026-10-05 (Oops 20261005-164023): "refactor the oops claude service
so it instead uses dayflow's screenshots? that way we dont have 2 services
taking screenshots consistently". Until then oops_ring.zsh ran its own
`screencapture` loop at 2 frames/s into a RAM disk, next to Dayflow's capture
of the same screen. Now Dayflow is the only thing taking screenshots, and this
script reads its frames for the 90 s before the trigger (oops.lua starts it
with hs.task right after writing keys.log).

  oops_dayflow.py <screens dir> <trigger epoch> <seconds> <where file>
    <where file>: lines "<epoch>\t<ws · app — window>" from oops.lua, one per
    change; deleted when done.
  Writes T-012.5s.jpg frames, ocr-list.txt and INDEX.txt (LAST, so its mtime
  says the frames are done; the oops launcher waits for it before OCR). Always
  writes INDEX.txt, with a "# …" line saying why when there are no frames.

Dayflow facts this relies on (checked 2026-10-05, Dayflow 2.6.0):
  * ~/Library/Application Support/Dayflow/recordings/*.mp4 are HEVC chunks of
    5-10 min of the ACTIVE display (1670x1080 built-in, 1920x1080 DELL). Table
    `screenshots` in chunks.sqlite has one row per frame: file_path,
    frame_index (0-based, contiguous, = decode order), captured_at (epoch),
    created_at (UTC text, inserted ~1-3 s after the capture).
  * The chunk being written has no moov yet (AVAssetWriter writes it at the
    end), so ffmpeg cannot open it, but its mdat already holds every frame as
    4-byte length-prefixed NAL units. The VPS/SPS/PPS live only in the moov,
    so they are borrowed from a closed chunk of the same resolution. A
    wrong-resolution donor decodes silently into garbage; under ffmpeg's
    strict error detection it reports "Error parsing NAL unit", so the donor
    is the one that decodes the open chunk with no warnings at all. Checked by
    stripping the moov from a closed chunk: 91/91 frames bit-identical to a
    normal decode.
  * With screenshotIntervalSeconds below 5 Dayflow still captures every 5 s
    but stamps frames `interval` apart, so captured_at drifts minutes behind.
    created_at is used whenever the two disagree by more than 10 s.
    (That was with a degraded replayd, 2026-10-05. With a healthy one, 1 s
    really is one frame a second, captured_at = created_at: checked
    2026-10-06 18:06.)
  * Since 2026-10-06 Dayflow saves a frame every second (Matt's rule, kept by
    dayflow-guard.nix). 90 frames for 90 s is too many to OCR and read, so
    frames are thinned: every frame in the last DENSE s before the trigger,
    then one per STEP s, plus the first frame after each window change.
    OOPS_DAYFLOW_DENSE / OOPS_DAYFLOW_STEP override them (lifelog's `frames`
    passes DENSE=0 and a STEP sized to the window). At the old 5-10 s cadence
    nothing is dropped.
"""
import datetime
import os
import shutil
import sqlite3
import struct
import subprocess
import sys
import tempfile

BIN = '/etc/profiles/per-user/matth/bin'
FFMPEG, FFPROBE = BIN + '/ffmpeg', BIN + '/ffprobe'
DAYFLOW = os.environ.get('OOPS_DAYFLOW_DIR', os.path.expanduser('~/Library/Application Support/Dayflow'))
STRICT = ['-err_detect', '+crccheck+bitstream+buffer+explode+careful']
START = b'\x00\x00\x00\x01'
DENSE = float(os.environ.get('OOPS_DAYFLOW_DENSE', '10'))
STEP = float(os.environ.get('OOPS_DAYFLOW_STEP', '5'))


def boxes(data):
    i = 0
    while i + 8 <= len(data):
        size, kind = struct.unpack('>I4s', data[i:i + 8])
        head = 8
        if size == 1:
            size, head = struct.unpack('>Q', data[i + 8:i + 16])[0], 16
        elif size == 0:  # mdat still being written: runs to EOF
            size = len(data) - i
        yield kind, i + head, i + size
        if size < head:
            return
        i += size


def is_closed(path):
    with open(path, 'rb') as f:
        return any(kind == b'moov' for kind, _, _ in boxes(f.read()))


def open_chunk_annexb(path):
    """The open chunk's mdat as an Annex-B stream, minus a NAL cut at the write edge."""
    with open(path, 'rb') as f:
        data = f.read()
    for kind, start, end in boxes(data):
        if kind == b'mdat':
            out, j = [], start
            while j + 4 <= end:
                n = struct.unpack('>I', data[j:j + 4])[0]
                if n == 0 or j + 4 + n > end:
                    break
                out.append(START + data[j + 4:j + 4 + n])
                j += 4 + n
            return b''.join(out)
    raise RuntimeError('no mdat in ' + os.path.basename(path))


def param_sets(closed_path):
    stream = subprocess.run([FFMPEG, '-v', 'error', '-i', closed_path, '-c', 'copy', '-bsf:v', 'hevc_mp4toannexb',
                             '-frames:v', '1', '-f', 'hevc', '-'], capture_output=True, check=True, timeout=20).stdout
    return b''.join(START + p.rstrip(b'\x00') for p in stream.split(START) if p and (p[0] >> 1) & 0x3f in (32, 33, 34))


def donors(open_path):
    """Newest closed chunk of each resolution, newest first."""
    rec = os.path.dirname(open_path)
    seen = set()
    for name in sorted(os.listdir(rec), reverse=True)[:60]:
        path = os.path.join(rec, name)
        if path == open_path or not name.endswith('.mp4'):
            continue
        probe = subprocess.run([FFPROBE, '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                                'stream=width,height', '-of', 'csv=p=0', path], capture_output=True, text=True, timeout=10)
        res = probe.stdout.strip()
        if probe.returncode == 0 and res and res not in seen:
            seen.add(res)
            yield path


def decode(src, first, last, outdir, fmt=None):
    """Frames first..last (decode order) of src as outdir/0001.jpg…"""
    cmd = [FFMPEG, '-v', 'error', '-y'] + (['-f', fmt] if fmt else []) + ['-i', src, '-vf', 'select=between(n\\,%d\\,%d)' % (first, last),
                                                                          '-fps_mode', 'passthrough', '-q:v', '3', os.path.join(outdir, '%04d.jpg')]
    subprocess.run(cmd, capture_output=True, check=True, timeout=60)
    return sorted(os.listdir(outdir))


def chunk_frames(path, first, last, tmp):
    outdir = tempfile.mkdtemp(dir=tmp)
    if is_closed(path):
        return [os.path.join(outdir, f) for f in decode(path, first, last, outdir)]
    body = open_chunk_annexb(path)
    for donor in donors(path):
        stream = os.path.join(tmp, 'open.hevc')
        with open(stream, 'wb') as f:
            f.write(param_sets(donor) + body)
        check = subprocess.run([FFMPEG, '-v', 'warning'] + STRICT + ['-f', 'hevc', '-i', stream, '-f', 'null', '-'],
                               capture_output=True, text=True, timeout=60)
        if check.returncode == 0 and not check.stderr.strip():
            return [os.path.join(outdir, f) for f in decode(stream, first, last, outdir, 'hevc')]
    raise RuntimeError('no closed chunk decodes ' + os.path.basename(path) + ' cleanly')


def frame_time(captured, created):
    made = datetime.datetime.strptime(created, '%Y-%m-%d %H:%M:%S').replace(tzinfo=datetime.timezone.utc).timestamp()
    return captured if abs(made - captured) <= 10 else made


def thin(items, trigger):
    """items: [(t, where)] sorted by t. The times to keep: everything in the
    last DENSE s, then the first frame of each STEP-s bucket (counted back
    from the trigger) and the first frame after each window change."""
    keep, bucket, where = set(), None, None
    for t, here in items:
        age = trigger - t
        b = int(age // STEP) if STEP > 0 else t
        if age <= DENSE or here != where or b != bucket:
            keep.add(t)
            bucket = b
        where = here
    return keep


def where_at(timeline, t):
    w = timeline[0][1] if timeline else '?'
    for at, here in timeline:
        if at <= t:
            w = here
        else:
            break
    return w


def main(screens, trigger, seconds, where_file):
    timeline = []
    if os.path.exists(where_file):
        with open(where_file) as f:
            for line in f:
                at, _, here = line.rstrip('\n').partition('\t')
                timeline.append((float(at), here))
    lo, hi = trigger - seconds, trigger + 1
    con = sqlite3.connect('file:%s/chunks.sqlite?mode=ro' % DAYFLOW, uri=True, timeout=5)
    rows = con.execute("select file_path, frame_index, captured_at, created_at from screenshots where is_deleted = 0 and "
                       "(captured_at between ? and ? or created_at between datetime(?, 'unixepoch') and datetime(?, 'unixepoch'))",
                       (lo, hi, lo, hi + 5)).fetchall()
    con.close()
    wanted = {}  # file -> {frame_index: time}
    for path, idx, captured, created in rows:
        t = frame_time(captured, created)
        if lo <= t <= hi:
            wanted.setdefault(path, {})[idx] = t
    if not wanted:
        return [], '# no Dayflow frames in the %d s before the trigger (is Dayflow recording?)' % seconds
    keep = thin(sorted((t, where_at(timeline, t)) for frames in wanted.values() for t in frames.values()), trigger)
    total = sum(len(frames) for frames in wanted.values())
    wanted = {path: {i: t for i, t in frames.items() if t in keep} for path, frames in wanted.items()}
    wanted = {path: frames for path, frames in wanted.items() if frames}
    tmp = tempfile.mkdtemp(prefix='oops-dayflow-')
    shots, notes = [], []
    try:
        for path, frames in wanted.items():
            first, last = min(frames), max(frames)
            try:
                files = chunk_frames(path, first, last, tmp)
            except Exception as e:  # one bad chunk must not cost the others
                notes.append('# %s frames %d-%d unreadable: %s' % (os.path.basename(path), first, last, e))
                continue
            for k, jpg in enumerate(files):
                t = frames.get(first + k)
                if t is None:  # thinned out, or not in the window
                    continue
                # created_at can land just after the trigger; T-000.0s.jpg is oops.lua's own frame
                name = 'T-%05.1fs.jpg' % max(trigger - t, 0.1)
                while os.path.exists(os.path.join(screens, name)):
                    name = name[:-4] + 'b.jpg'
                shutil.move(jpg, os.path.join(screens, name))
                shots.append((t, name, where_at(timeline, t)))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    shots.sort()
    if len(shots) < total:
        notes.append('# kept %d of %d frames: every frame in the last %g s, then one per %g s, plus each window change'
                     % (len(shots), total, DENSE, STEP))
    return shots, '\n'.join(notes)


if __name__ == '__main__':
    screens, trigger, seconds, where_file = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
    try:
        shots, note = main(screens, trigger, seconds, where_file)
    except Exception as e:
        shots, note = [], '# Dayflow frames failed: %r' % (e,)
    lines = ['# Dayflow frames for the %d s before the trigger' % seconds]
    lines += [note] if note else []
    lines += ['%s  %s' % (name, where) for _, name, where in shots]
    ocr = [name for _, name, _ in shots]
    tail = os.path.join(screens, 'INDEX.tail')  # the frame oops.lua grabbed at the trigger itself
    if os.path.exists(tail):
        with open(tail) as f:
            lines.append(f.read().rstrip('\n'))
        os.remove(tail)
        ocr.append('T-000.0s.jpg')
        # full-resolution screencapture (3456 px on the built-in); half is plenty
        subprocess.run(['/usr/bin/sips', '-Z', '1728', os.path.join(screens, 'T-000.0s.jpg')], capture_output=True, timeout=30)
    with open(os.path.join(screens, 'ocr-list.txt'), 'w') as f:
        f.write('\n'.join(ocr) + '\n')
    if os.path.exists(where_file):
        os.remove(where_file)
    with open(os.path.join(screens, 'INDEX.txt.part'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    os.replace(os.path.join(screens, 'INDEX.txt.part'), os.path.join(screens, 'INDEX.txt'))
