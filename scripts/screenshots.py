"""Renders README screenshots, the mode-switch GIF and the social preview from dist/marko-demo-local.html.
Uses Inter / Newsreader / JetBrains Mono as stand-ins for SF Pro / New York / SF Mono so the images match a Mac."""
import asyncio, pathlib, io
from playwright.async_api import async_playwright
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONTS = pathlib.Path('/tmp/claude-0/-home-claude/376daf08-d74a-56e8-868d-9e2cdbf6468a/scratchpad/mdv/vendor/node_modules/@fontsource')
OUT = ROOT / 'docs' / 'screenshots'; OUT.mkdir(parents=True, exist_ok=True)
PAGE = (ROOT / 'dist' / 'marko-demo-local.html').as_uri()

def face(family, file, weight):
    return f"@font-face{{font-family:'{family}';src:url('{(FONTS / file).as_uri()}') format('woff2');font-weight:{weight};font-style:normal}}"
CSS = ''.join([
    *[face('SF Pro Text', f'inter/files/inter-latin-{w}-normal.woff2', w) for w in (400, 500, 600, 700)],
    *[face('New York', f'newsreader/files/newsreader-latin-{w}-normal.woff2', w) for w in (400, 500, 600)],
    *[face('SF Mono', f'jetbrains-mono/files/jetbrains-mono-latin-{w}-normal.woff2', w) for w in (400, 500)],
    ":root{--sans:'SF Pro Text',sans-serif;--serif:'New York',serif;--mono:'SF Mono',monospace} #toast{display:none!important}",
])

async def setup(pg, dark=False):
    await pg.emulate_media(color_scheme='dark' if dark else 'light')
    await pg.goto(PAGE); await pg.add_style_tag(content=CSS); await pg.wait_for_timeout(900)
    await pg.evaluate("localStorage.clear()")

async def open_sample(pg, i):
    await pg.click('#btn-open'); await pg.wait_for_timeout(120)
    await pg.click(f'#open-menu [data-open="sample"][data-i="{i}"]'); await pg.wait_for_timeout(600)

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch()
        pg = await b.new_page(viewport={'width': 1400, 'height': 860}, device_scale_factor=2)

        # 1. Hero: plan sample in Plan mode with both sidebars open, light
        await setup(pg); await open_sample(pg, 2)
        await pg.keyboard.press('2'); await pg.wait_for_timeout(200)
        await pg.click('#btn-outline'); await pg.click('#btn-inspector'); await pg.wait_for_timeout(300)
        await pg.screenshot(path=str(OUT / 'plan-mode.png'))

        # 2. Reading mode, light, outline open
        await open_sample(pg, 1); await pg.keyboard.press('1'); await pg.wait_for_timeout(200)
        if 'hide-outline' in (await pg.get_attribute('#app', 'class')): await pg.click('#btn-outline')
        if 'hide-inspector' not in (await pg.get_attribute('#app', 'class')): await pg.click('#btn-inspector')
        await pg.wait_for_timeout(300)
        await pg.screenshot(path=str(OUT / 'reading-mode.png'))

        # 3. Interactive mode, dark, search active with panel
        await setup(pg, dark=True); await open_sample(pg, 0); await pg.keyboard.press('3'); await pg.wait_for_timeout(200)
        await pg.click('#btn-outline'); await pg.click('#btn-inspector')
        await pg.fill('#search', 'hook'); await pg.wait_for_timeout(400)
        await pg.hover('.sec:not(.hidden-by-search) > .sec-head'); await pg.wait_for_timeout(150)
        await pg.screenshot(path=str(OUT / 'interactive-mode-dark.png'))

        # 4. GIF: Reading → Plan → Interactive on the plan sample (light)
        pg2 = await b.new_page(viewport={'width': 1200, 'height': 720}, device_scale_factor=1)
        await setup(pg2); await open_sample(pg2, 2)
        await pg2.click('#btn-outline'); await pg2.wait_for_timeout(200)
        frames, durations = [], []
        async def snap(ms):
            frames.append(Image.open(io.BytesIO(await pg2.screenshot())).convert('P', palette=Image.ADAPTIVE, colors=192)); durations.append(ms)
        for key, hold in (('1', 1600), ('2', 2200), ('3', 1600)):
            await pg2.keyboard.press(key); await pg2.wait_for_timeout(350); await snap(hold)
        await pg2.click('#btn-inspector'); await pg2.wait_for_timeout(300); await snap(1400)
        await pg2.fill('#search', 'hook'); await pg2.wait_for_timeout(400); await snap(1800)
        frames[0].save(str(OUT / 'modes.gif'), save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True)

        # 5. Social preview 1280×640: hero crop + wordmark
        hero = Image.open(OUT / 'plan-mode.png').convert('RGB')
        card = Image.new('RGB', (1280, 640), '#F5F5F7')
        crop = hero.crop((470, 0, 2800, 1720))               # canvas + panel, no outline rail
        shot = crop.resize((640, int(640 * crop.height / crop.width)), Image.LANCZOS)
        card.paste(shot, (620, 60))
        ImageDraw.Draw(card).rectangle((619, 59, 620 + shot.width, 60 + shot.height), outline='#D9D9DE')
        icon = Image.open(ROOT / 'app' / 'mac' / 'icon.png').convert('RGBA').resize((110, 110), Image.LANCZOS)
        card.paste(icon, (60, 70), icon)
        d = ImageDraw.Draw(card)
        try:
            big = ImageFont.truetype(str(FONTS / 'inter/files/inter-latin-700-normal.woff2'), 60)
            med = ImageFont.truetype(str(FONTS / 'inter/files/inter-latin-500-normal.woff2'), 26)
        except Exception:
            big = med = ImageFont.load_default()
        d.text((190, 90), 'Marko', fill='#1D1D1F', font=big)
        d.text((62, 230), 'A Markdown viewer for', fill='#1D1D1F', font=med)
        d.text((62, 266), 'what Claude writes.', fill='#1D1D1F', font=med)
        d.text((62, 330), 'Reading · Plan · Interactive', fill='#0071E3', font=med)
        d.text((62, 400), 'Claude Code plugin · npm', fill='#6E6E73', font=med)
        d.text((62, 436), 'Mac & Windows apps', fill='#6E6E73', font=med)
        card.save(str(OUT / 'social-preview.png'), optimize=True)
        await b.close()
    for f in sorted(OUT.iterdir()): print(f.name, f'{f.stat().st_size // 1024} KB')
asyncio.run(main())
