#!/usr/bin/env python3
"""Generate TashGuides textures (uncompressed 32-bit TGA, power-of-two sizes).

White shapes with a dark outline so the addon can tint them with SetVertexColor.
Run:  python3 tools/make_media.py   -> writes TashGuides/media/*.tga
"""
import math
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), "..", "TashGuides", "media")
SS = 4  # supersampling factor for anti-aliasing


def write_tga(path, w, h, pixels):
    # pixels: list of rows (top to bottom) of (r, g, b, a) 0-255
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    with open(path, "wb") as f:
        f.write(header)
        for row in pixels:
            for r, g, b, a in row:
                f.write(bytes((b, g, r, a)))


def render(size, shade):
    """shade(x, y) -> (r, g, b, a) floats 0..1 in unit coords (0..1, y down)."""
    rows = []
    for py in range(size):
        row = []
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(SS):
                for sx in range(SS):
                    x = (px + (sx + 0.5) / SS) / size
                    y = (py + (sy + 0.5) / SS) / size
                    r, g, b, a = shade(x, y)
                    acc[0] += r * a
                    acc[1] += g * a
                    acc[2] += b * a
                    acc[3] += a
            n = SS * SS
            a = acc[3] / n
            if a > 0:
                r, g, b = (acc[0] / n) / a, (acc[1] / n) / a, (acc[2] / n) / a
            else:
                r = g = b = 0
            row.append(tuple(int(max(0, min(1, v)) * 255 + 0.5) for v in (r, g, b, a)))
        rows.append(row)
    return rows


def point_in_poly(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def dist_to_poly_edge(x, y, poly):
    best = 1e9
    for i in range(len(poly)):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % len(poly)]
        dx, dy = x2 - x1, y2 - y1
        t = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - (x1 + t * dx), y - (y1 + t * dy)))
    return best


def arrow():
    # Upward-pointing arrowhead with a notched tail, like a compass needle.
    poly = [(0.5, 0.06), (0.88, 0.86), (0.5, 0.68), (0.12, 0.86)]
    outline = 0.045

    def shade(x, y):
        inside = point_in_poly(x, y, poly)
        d = dist_to_poly_edge(x, y, poly)
        if inside and d > outline:
            # subtle vertical highlight on the left half for depth
            lift = 1.0 if x < 0.5 else 0.82
            return (lift, lift, lift, 1.0)
        if inside or d <= outline * 0.6:
            return (0.05, 0.05, 0.05, 1.0)
        return (0, 0, 0, 0)

    return render(64, shade)


def dot():
    def shade(x, y):
        d = math.hypot(x - 0.5, y - 0.5)
        if d < 0.34:
            return (1, 1, 1, 1)
        if d < 0.45:
            return (0.05, 0.05, 0.05, 1)
        return (0, 0, 0, 0)

    return render(32, shade)


def target():
    # Ring with a center dot: the guide waypoint marker.
    def shade(x, y):
        d = math.hypot(x - 0.5, y - 0.5)
        if d < 0.12:
            return (1, 1, 1, 1)
        if 0.12 <= d < 0.17:
            return (0.05, 0.05, 0.05, 1)
        if 0.27 <= d < 0.38:
            return (1, 1, 1, 1)
        if 0.22 <= d < 0.43:
            return (0.05, 0.05, 0.05, 1)
        return (0, 0, 0, 0)

    return render(32, shade)


def bang():
    # Questie-style "!" (available quest), white with dark outline.
    bar = [(0.38, 0.08), (0.62, 0.08), (0.57, 0.64), (0.43, 0.64)]

    def shade(x, y):
        in_bar = point_in_poly(x, y, bar)
        d_bar = dist_to_poly_edge(x, y, bar)
        dd = math.hypot(x - 0.5, y - 0.83)
        if (in_bar and d_bar > 0.05) or dd < 0.08:
            return (1, 1, 1, 1)
        if in_bar or d_bar < 0.05 or dd < 0.13:
            return (0.05, 0.05, 0.05, 1)
        return (0, 0, 0, 0)

    return render(32, shade)


def question():
    # "?" (quest ready to turn in), white with dark outline.
    cx, cy, rr, th = 0.5, 0.33, 0.2, 0.09

    def fill(x, y):
        d = math.hypot(x - cx, y - cy)
        ang = math.degrees(math.atan2(y - cy, x - cx))  # 0 = right, 90 = down
        # Arc runs from the left side, over the top, round the right and down to the
        # bottom centre; the lower-left quarter stays open.
        arc = abs(d - rr) < th and not (90 < ang < 165)
        stem = abs(x - 0.5) < th * 0.8 and cy + rr - th * 0.5 <= y <= 0.66
        dotp = math.hypot(x - 0.5, y - 0.84) < 0.085
        return arc or stem or dotp

    def shade(x, y):
        if fill(x, y):
            return (1, 1, 1, 1)
        for dx, dy in ((0.05, 0), (-0.05, 0), (0, 0.05), (0, -0.05), (0.035, 0.035), (-0.035, 0.035), (0.035, -0.035), (-0.035, -0.035)):
            if fill(x + dx, y + dy):
                return (0.05, 0.05, 0.05, 1)
        return (0, 0, 0, 0)

    return render(32, shade)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn, size in (("arrow", arrow, 64), ("dot", dot, 32), ("target", target, 32),
                           ("available", bang, 32), ("turnin", question, 32)):
        write_tga(os.path.join(OUT, name + ".tga"), size, size, fn())
        print("wrote", name + ".tga")


if __name__ == "__main__":
    main()
