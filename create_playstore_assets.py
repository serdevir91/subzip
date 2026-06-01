"""
SubZip - Play Store Marketing Assets Generator
Creates professional Play Store screenshots, icon, and feature graphic.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import math

# ============================================================
# CONFIG
# ============================================================
OUTPUT_DIR = r"c:\Users\serde\OneDrive\Belgeler\Desktop\Code\supzip\playstore_assets"
SS_DIR = r"c:\Users\serde\OneDrive\Belgeler\Desktop\Code\supzip\ss"
ICON_SRC = r"c:\Users\serde\.gemini\antigravity\brain\d2ed19d4-1095-4cf2-ac29-32595c018568\subzip_icon_fixed_1780136729740.png"

CANVAS_W, CANVAS_H = 1080, 1920
ACCENT_BLUE = (33, 150, 243)  # #2196F3

# Gradient colors (dark blue theme matching the app)
GRAD_TOP = (8, 18, 35)       # Very dark navy
GRAD_BOTTOM = (12, 35, 64)   # Slightly lighter dark blue

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ============================================================
# FONT HELPERS
# ============================================================
def get_font(size, bold=True):
    """Try to load Arial Bold, fallback to Arial, then default."""
    font_paths = [
        r"C:\Windows\Fonts\arialbd.ttf",
        r"C:\Windows\Fonts\arial.ttf",
        r"C:\Windows\Fonts\segoeui.ttf",
        r"C:\Windows\Fonts\calibri.ttf",
    ]
    if not bold:
        font_paths = [
            r"C:\Windows\Fonts\arial.ttf",
            r"C:\Windows\Fonts\segoeui.ttf",
            r"C:\Windows\Fonts\calibri.ttf",
        ]
    for fp in font_paths:
        if os.path.exists(fp):
            return ImageFont.truetype(fp, size)
    return ImageFont.load_default()

# ============================================================
# GRADIENT BACKGROUND
# ============================================================
def create_gradient_background(width, height, top_color, bottom_color):
    """Create a vertical gradient image."""
    img = Image.new("RGB", (width, height))
    pixels = img.load()
    for y in range(height):
        ratio = y / height
        r = int(top_color[0] + (bottom_color[0] - top_color[0]) * ratio)
        g = int(top_color[1] + (bottom_color[1] - top_color[1]) * ratio)
        b = int(top_color[2] + (bottom_color[2] - top_color[2]) * ratio)
        for x in range(width):
            pixels[x, y] = (r, g, b)
    return img

# ============================================================
# ROUNDED CORNERS
# ============================================================
def add_rounded_corners(img, radius):
    """Add rounded corners to an image using an alpha mask."""
    img = img.convert("RGBA")
    w, h = img.size
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (w, h)], radius=radius, fill=255)
    img.putalpha(mask)
    return img

# ============================================================
# DROP SHADOW
# ============================================================
def add_drop_shadow(img, offset=(0, 10), shadow_color=(0, 0, 0, 100), blur_radius=20):
    """Add a drop shadow behind an RGBA image."""
    w, h = img.size
    # Create shadow canvas (larger to accommodate blur)
    pad = blur_radius * 2
    shadow_canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    
    # Create shadow shape from alpha channel
    shadow = Image.new("RGBA", (w, h), shadow_color)
    # Use the original image's alpha as mask
    shadow.putalpha(img.split()[3])
    
    shadow_canvas.paste(shadow, (pad + offset[0], pad + offset[1]))
    shadow_canvas = shadow_canvas.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    
    # Composite original on top of shadow
    result = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    result = Image.alpha_composite(result, shadow_canvas)
    result.paste(img, (pad, pad), img)
    
    return result, pad

# ============================================================
# ACCENT LINE (subtle decorative element)
# ============================================================
def draw_accent_line(draw, y, width, color, thickness=3):
    """Draw a thin accent line across the canvas."""
    line_w = 120
    x_start = (width - line_w) // 2
    draw.rounded_rectangle(
        [(x_start, y), (x_start + line_w, y + thickness)],
        radius=2,
        fill=color
    )

# ============================================================
# CREATE SCREENSHOT
# ============================================================
def create_screenshot(ss_path, title, subtitle, output_path):
    """Create a single Play Store marketing screenshot."""
    print(f"  Creating: {os.path.basename(output_path)}")
    
    # Create gradient background
    bg = create_gradient_background(CANVAS_W, CANVAS_H, GRAD_TOP, GRAD_BOTTOM)
    draw = ImageDraw.Draw(bg)
    
    # --- Draw accent line at the very top ---
    draw_accent_line(draw, 50, CANVAS_W, ACCENT_BLUE, thickness=4)
    
    # --- Title ---
    title_font = get_font(72, bold=True)
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_w = title_bbox[2] - title_bbox[0]
    title_x = (CANVAS_W - title_w) // 2
    title_y = 100
    draw.text((title_x, title_y), title, fill=(255, 255, 255), font=title_font)
    
    # --- Subtitle ---
    subtitle_font = get_font(38, bold=False)
    sub_bbox = draw.textbbox((0, 0), subtitle, font=subtitle_font)
    sub_w = sub_bbox[2] - sub_bbox[0]
    sub_x = (CANVAS_W - sub_w) // 2
    sub_y = title_y + 100
    draw.text((sub_x, sub_y), subtitle, fill=(180, 200, 220), font=subtitle_font)
    
    # --- Load and place screenshot ---
    ss = Image.open(ss_path).convert("RGBA")
    
    # Calculate screenshot placement
    # Available area for screenshot
    ss_top_margin = sub_y + 80  # Start below subtitle
    ss_bottom_margin = 40
    available_h = CANVAS_H - ss_top_margin - ss_bottom_margin
    
    # Scale screenshot to fit width with padding
    ss_padding = 80  # side padding
    target_w = CANVAS_W - (ss_padding * 2)
    
    # Scale proportionally
    scale = target_w / ss.width
    new_w = int(ss.width * scale)
    new_h = int(ss.height * scale)
    
    # If screenshot is too tall, scale down further
    if new_h > available_h:
        scale = available_h / ss.height
        new_w = int(ss.width * scale)
        new_h = int(ss.height * scale)
    
    ss_resized = ss.resize((new_w, new_h), Image.LANCZOS)
    
    # Add rounded corners
    corner_radius = 30
    ss_rounded = add_rounded_corners(ss_resized, corner_radius)
    
    # Add drop shadow
    ss_with_shadow, pad = add_drop_shadow(ss_rounded, offset=(0, 8), 
                                           shadow_color=(0, 0, 0, 120), 
                                           blur_radius=25)
    
    # Center horizontally, position below subtitle
    ss_x = (CANVAS_W - ss_with_shadow.width) // 2
    ss_y = ss_top_margin + (available_h - ss_with_shadow.height) // 2
    
    # Ensure it doesn't go above the subtitle area
    ss_y = max(ss_y, ss_top_margin)
    
    # Paste onto background
    bg = bg.convert("RGBA")
    bg.paste(ss_with_shadow, (ss_x, ss_y), ss_with_shadow)
    
    # --- Subtle bottom accent glow ---
    glow_draw = ImageDraw.Draw(bg)
    # Draw a subtle gradient glow at the bottom
    for i in range(60):
        alpha = int(15 * (1 - i / 60))
        glow_color = (ACCENT_BLUE[0], ACCENT_BLUE[1], ACCENT_BLUE[2], alpha)
        y_pos = CANVAS_H - 60 + i
        glow_draw.line([(0, y_pos), (CANVAS_W, y_pos)], fill=glow_color)
    
    # Save as RGB
    final = bg.convert("RGB")
    final.save(output_path, "PNG", quality=95)
    print(f"    [OK] Saved: {output_path}")

# ============================================================
# CREATE PLAY STORE ICON (512x512)
# ============================================================
def create_play_icon(src_path, output_path):
    """Create a 512x512 Play Store icon."""
    print(f"  Creating: {os.path.basename(output_path)}")
    
    icon = Image.open(src_path).convert("RGBA")
    icon = icon.resize((512, 512), Image.LANCZOS)
    
    # Save directly - the source icon already has the right design
    icon.save(output_path, "PNG")
    print(f"    [OK] Saved: {output_path}")

# ============================================================
# CREATE FEATURE GRAPHIC (1024x500)
# ============================================================
def create_feature_graphic(output_path):
    """Create a 1024x500 feature graphic."""
    print(f"  Creating: {os.path.basename(output_path)}")
    
    W, H = 1024, 500
    
    # Create gradient background
    bg = create_gradient_background(W, H, GRAD_TOP, GRAD_BOTTOM)
    bg = bg.convert("RGBA")
    draw = ImageDraw.Draw(bg)
    
    # --- Add subtle geometric accents ---
    # Draw faint circles as decorative elements
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ov_draw = ImageDraw.Draw(overlay)
    
    # Large subtle circle on the right
    circle_color = (ACCENT_BLUE[0], ACCENT_BLUE[1], ACCENT_BLUE[2], 15)
    ov_draw.ellipse([(620, -100), (1150, 430)], fill=circle_color)
    
    # Smaller circle on the left
    circle_color2 = (ACCENT_BLUE[0], ACCENT_BLUE[1], ACCENT_BLUE[2], 10)
    ov_draw.ellipse([(-80, 200), (250, 530)], fill=circle_color2)
    
    bg = Image.alpha_composite(bg, overlay)
    draw = ImageDraw.Draw(bg)
    
    # --- Load and place app icon on the left ---
    try:
        icon = Image.open(ICON_SRC).convert("RGBA")
        icon_size = 200
        icon = icon.resize((icon_size, icon_size), Image.LANCZOS)
        icon = add_rounded_corners(icon, 40)
        
        icon_x = 120
        icon_y = (H - icon_size) // 2
        bg.paste(icon, (icon_x, icon_y), icon)
        
        text_left = icon_x + icon_size + 60
    except Exception:
        text_left = 120
    
    # --- App Name ---
    name_font = get_font(96, bold=True)
    name_y = H // 2 - 80
    draw = ImageDraw.Draw(bg)
    draw.text((text_left, name_y), "SubZip", fill=(255, 255, 255), font=name_font)
    
    # --- Tagline ---
    tag_font = get_font(36, bold=False)
    tag_y = name_y + 110
    draw.text((text_left, tag_y), "File Manager & Archive Tool", 
              fill=(150, 180, 210), font=tag_font)
    
    # --- Accent line under tagline ---
    line_y = tag_y + 55
    draw.rounded_rectangle(
        [(text_left, line_y), (text_left + 200, line_y + 4)],
        radius=2,
        fill=ACCENT_BLUE
    )
    
    # Save
    final = bg.convert("RGB")
    final.save(output_path, "PNG", quality=95)
    print(f"    [OK] Saved: {output_path}")

# ============================================================
# MAIN
# ============================================================
def main():
    print("=" * 60)
    print("SubZip - Play Store Marketing Assets Generator")
    print("=" * 60)
    
    screenshots = [
        {
            "source": os.path.join(SS_DIR, "ss.png"),
            "title": "STORAGE OVERVIEW",
            "subtitle": "Monitor disk usage & largest files",
            "output": os.path.join(OUTPUT_DIR, "screenshot_1.png"),
        },
        {
            "source": os.path.join(SS_DIR, "ss1.png"),
            "title": "FILE EXPLORER",
            "subtitle": "Browse, search & manage all your files",
            "output": os.path.join(OUTPUT_DIR, "screenshot_2.png"),
        },
        {
            "source": os.path.join(SS_DIR, "ss2.png"),
            "title": "FAVORITES",
            "subtitle": "Quick access to your starred items",
            "output": os.path.join(OUTPUT_DIR, "screenshot_3.png"),
        },
        {
            "source": os.path.join(SS_DIR, "ss3.png"),
            "title": "BACKGROUND TASKS",
            "subtitle": "Track copy, move & extract operations",
            "output": os.path.join(OUTPUT_DIR, "screenshot_4.png"),
        },
    ]
    
    print("\n[*] Generating Play Store Screenshots...")
    for ss in screenshots:
        create_screenshot(ss["source"], ss["title"], ss["subtitle"], ss["output"])
    
    print("\n[*] Generating Play Store Icon (512x512)...")
    create_play_icon(ICON_SRC, os.path.join(OUTPUT_DIR, "play_icon_512.png"))
    
    print("\n[*] Generating Feature Graphic (1024x500)...")
    create_feature_graphic(os.path.join(OUTPUT_DIR, "feature_graphic.png"))
    
    print("\n" + "=" * 60)
    print("[OK] All assets generated successfully!")
    print(f"[->] Output directory: {OUTPUT_DIR}")
    print("=" * 60)

if __name__ == "__main__":
    main()
