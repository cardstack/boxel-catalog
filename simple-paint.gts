// ═══ [EDIT TRACKING: ON] Mark all changes with ⁿ ═══
import {
  CardDef,
  field,
  contains,
  Component,
} from 'https://cardstack.com/base/card-api'; // ¹ Core imports
import StringField from 'https://cardstack.com/base/string';
import BooleanField from 'https://cardstack.com/base/boolean';
import { on } from '@ember/modifier';
import { fn } from '@ember/helper';
import { eq } from '@cardstack/boxel-ui/helpers'; // ³ Import missing helper used in template
import { tracked } from '@glimmer/tracking'; // ³a track drawing state
import PaletteIcon from '@cardstack/boxel-icons/palette'; // ² Icon import

export class SimpleDrawing extends CardDef {
  // ³ Drawing card with working functionality
  static displayName = 'Simple Drawing';
  static icon = PaletteIcon;

  @field artworkTitle = contains(StringField); // ⁴ Core fields
  @field selectedColor = contains(StringField);
  @field drawingData = contains(StringField); // ⁴a Serialized "x,y,color;..." points
  @field brushSize = contains(StringField); // ³⁰ Brush size: small/medium/large
  @field isPublic = contains(BooleanField);

  // ⁵ Computed title
  @field cardTitle = contains(StringField, {
    computeVia: function (this: SimpleDrawing) {
      return this.artworkTitle ?? 'Untitled Drawing';
    },
  });

  static isolated = class Isolated extends Component<typeof SimpleDrawing> {
    // ⁶ Full drawing interface
    // ⁷ Color selection action
    selectColor = (color: string) => {
      // selecting a color disables eraser
      this.isEraser = false;
      if (this.args.model) {
        this.args.model.selectedColor = color;
      }
    };

    // ⁸ Update title action
    updateTitle = (event: Event) => {
      const target = event.target as HTMLInputElement;
      if (this.args.model) {
        this.args.model.artworkTitle = target.value;
      }
    };

    // ⁹ Toggle public action
    togglePublic = (event: Event) => {
      const target = event.target as HTMLInputElement;
      if (this.args.model) {
        this.args.model.isPublic = target.checked;
      }
    };

    @tracked isDrawing = false;
    @tracked brushSize = 'medium'; // ³¹ Track current brush size
    @tracked isEraser = false; // ³² Track eraser mode
    @tracked showPalette = true; // Palette visibility
    @tracked hasDrawn = false; // Hide help overlay after first stroke

    togglePalette = () => {
      this.showPalette = !this.showPalette;
    };

    // ³³ Brush size options
    brushSizes = [
      { value: 'small', label: 'Small', size: 6 },
      { value: 'medium', label: 'Medium', size: 12 },
      { value: 'large', label: 'Large', size: 18 },
      { value: 'xl', label: 'XL', size: 24 },
    ];

    // ³⁴ Get current brush size in pixels
    get currentBrushSize() {
      const sizeObj = this.brushSizes.find((s) => s.value === this.brushSize);
      return sizeObj ? sizeObj.size : 12;
    }

    // ³⁵ Actions for new features
    selectBrushSize = (size: string) => {
      this.brushSize = size;
      if (this.args.model) {
        this.args.model.brushSize = size;
      }
    };

    toggleEraser = () => {
      this.isEraser = !this.isEraser;
    };

    downloadPNG = () => {
      const canvas = this.renderToCanvas(800, 600);
      const link = document.createElement('a');
      link.download = `${this.args.model?.artworkTitle || 'artwork'}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
    };

    // Render current dots to an offscreen canvas
    renderToCanvas(width: number, height: number): HTMLCanvasElement {
      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d');
      if (!ctx) return canvas;

      canvas.width = width;
      canvas.height = height;

      // White background
      ctx.fillStyle = 'white';
      ctx.fillRect(0, 0, canvas.width, canvas.height);

      // Draw each dot
      this.dots.forEach((dot) => {
        if (dot.color === 'transparent') return; // skip eraser dots in export
        ctx.fillStyle = dot.color;
        const x = (parseFloat(dot.x) / 100) * canvas.width;
        const y = (parseFloat(dot.y) / 100) * canvas.height;
        const radius = dot.size ? parseInt(dot.size, 10) / 2 : 6;

        ctx.beginPath();
        ctx.arc(x, y, radius, 0, 2 * Math.PI);
        ctx.fill();
      });

      return canvas;
    }

    // Update thumbnailURL on the card (and cardInfo.thumbnailURL when available)
    updateThumbnail = () => {
      try {
        const canvas = this.renderToCanvas(800, 600);
        const dataURL = canvas.toDataURL('image/png');
        if (this.args.model) {
          this.args.model.cardThumbnailURL = dataURL;
          // Best-effort update cardInfo.thumbnailURL if present
          try {
            // @ts-ignore - cardInfo may exist on instances
            if (this.args.model.cardInfo) {
              // @ts-ignore
              this.args.model.cardInfo.cardThumbnailURL = dataURL;
            }
          } catch (_e) {
            // ignore if not present
          }
        }
      } catch (_err) {
        // no-op on thumbnail failures
      }
    };

    // Internal: add a point from Mouse or Touch event
    addPointFromEvent = (event: MouseEvent | TouchEvent) => {
      let clientX: number | null = null;
      let clientY: number | null = null;

      if (event instanceof TouchEvent) {
        const t = event.touches[0] || event.changedTouches[0];
        if (!t) return;
        clientX = t.clientX;
        clientY = t.clientY;
        event.preventDefault();
      } else {
        clientX = (event as MouseEvent).clientX;
        clientY = (event as MouseEvent).clientY;
      }

      const target = event.currentTarget as HTMLElement;
      const rect = target.getBoundingClientRect();
      const x = (((clientX! - rect.left) / rect.width) * 100).toFixed(1);
      const y = (((clientY! - rect.top) / rect.height) * 100).toFixed(1);
      const color = this.isEraser
        ? 'transparent'
        : this.args.model?.selectedColor || '#3b82f6';
      const size = this.currentBrushSize;

      const point = `${x},${y},${color},${size}`;
      const current = this.args.model?.drawingData || '';

      const updated = current ? `${current};${point}` : point;
      if (this.args.model) this.args.model.drawingData = updated;
      if (!this.hasDrawn) this.hasDrawn = true; // hide help after first mark
    };

    // Click to place a single dot
    addDot = (event: MouseEvent) => {
      this.addPointFromEvent(event);
      this.updateThumbnail();
    };

    // Start a new stroke, append a stroke separator if needed, and add first point
    startDraw = (event: MouseEvent | TouchEvent) => {
      const current = this.args.model?.drawingData ?? '';
      const needsSeparator =
        current.length > 0 && !current.endsWith('|') && !current.endsWith(';');
      if (needsSeparator && this.args.model) {
        this.args.model.drawingData = `${current}|`;
      }
      this.isDrawing = true;
      this.addPointFromEvent(event);
    };

    // While drawing, keep adding points
    moveDraw = (event: MouseEvent | TouchEvent) => {
      if (!this.isDrawing) return;
      this.addPointFromEvent(event);
    };

    // End the current stroke
    endDraw = () => {
      this.isDrawing = false;
      this.updateThumbnail();
    };

    // Clear only the dots
    clearDots = () => {
      if (this.args.model) this.args.model.drawingData = '';
      this.updateThumbnail();
    };

    // Undo last stroke
    undoLastStroke = () => {
      const data = this.args.model?.drawingData || '';
      if (!data) return;

      if (data.includes('|')) {
        const strokes = data.split('|').filter((s) => s.trim() !== '');
        strokes.pop();
        if (this.args.model) this.args.model.drawingData = strokes.join('|');
      } else {
        if (this.args.model) this.args.model.drawingData = '';
      }
      this.updateThumbnail();
    };

    // Parse drawingData into a list of dot objects (supports optional '|' stroke separators)
    get dots() {
      const data = this.args.model?.drawingData;
      if (!data) return [];
      const normalized = data.replaceAll('|', ';');
      return normalized
        .split(';')
        .map((entry) => {
          const parts = entry.split(',');
          const [x, y, color] = parts;
          const size = parts[3] || '12'; // Default size for older dots
          if (!x || !y || !color) return null;
          return { x, y, color, size };
        })
        .filter(Boolean) as Array<{
        x: string;
        y: string;
        color: string;
        size: string;
      }>;
    }

    <template>
      <div class='drawing-workspace'>

        <div class='main-workspace {{if this.showPalette "" "no-palette"}}'>
          <div class='color-panel'>
            <h3>Colors</h3>
            <div class='color-grid'>
              <!-- Eraser swatch -->
              <button
                class='swatch eraser {{if this.isEraser "selected"}}'
                aria-label='Eraser'
                title='Eraser'
                {{on 'click' this.toggleEraser}}
              >
                <svg
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <!-- Classic tilted eraser shape -->
                  <path d='M16 3l5 5-9 9H7L2 12l9-9z'></path>
                  <path d='M7 17h5'></path>
                </svg>
              </button>

              <button
                class='swatch
                  {{if (eq @model.selectedColor "#ef4444") "selected"}}'
                style='background-color:#ef4444'
                aria-label='Red'
                {{on 'click' (fn this.selectColor '#ef4444')}}
              ></button>
              <button
                class='swatch
                  {{if (eq @model.selectedColor "#3b82f6") "selected"}}'
                style='background-color:#3b82f6'
                aria-label='Blue'
                {{on 'click' (fn this.selectColor '#3b82f6')}}
              ></button>
              <button
                class='swatch
                  {{if (eq @model.selectedColor "#22c55e") "selected"}}'
                style='background-color:#22c55e'
                aria-label='Green'
                {{on 'click' (fn this.selectColor '#22c55e')}}
              ></button>
              <button
                class='swatch
                  {{if (eq @model.selectedColor "#8b5cf6") "selected"}}'
                style='background-color:#8b5cf6'
                aria-label='Purple'
                {{on 'click' (fn this.selectColor '#8b5cf6')}}
              ></button>
              <button
                class='swatch
                  {{if (eq @model.selectedColor "#f97316") "selected"}}'
                style='background-color:#f97316'
                aria-label='Orange'
                {{on 'click' (fn this.selectColor '#f97316')}}
              ></button>
              <button
                class='swatch
                  {{if (eq @model.selectedColor "#ec4899") "selected"}}'
                style='background-color:#ec4899'
                aria-label='Pink'
                {{on 'click' (fn this.selectColor '#ec4899')}}
              ></button>
            </div>

            <!-- ⁴⁸ Brush size controls -->
            <div class='brush-section'>
              <h3>Brush Size</h3>
              <div class='brush-sizes'>
                {{#each this.brushSizes as |opt|}}
                  <button
                    class='brush-dot-btn
                      {{if (eq this.brushSize opt.value) "active"}}'
                    {{on 'click' (fn this.selectBrushSize opt.value)}}
                    aria-label={{opt.label}}
                    title={{opt.label}}
                  >
                    <span
                      class='dot-demo'
                      style='width: {{opt.size}}px; height: {{opt.size}}px;'
                    ></span>
                  </button>
                {{/each}}
              </div>
            </div>

            <div class='panel-tools'>
              <button
                class='tool-ico'
                title='Clear'
                aria-label='Clear'
                {{on 'click' this.clearDots}}
              >
                <svg
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <polyline points='3,6 5,6 21,6' />
                  <path d='M19,6v14a2,2,0,0,1-2,2H7a2,2,0,0,1-2-2V6' />
                </svg>
              </button>
              <button
                class='tool-ico'
                title='Undo'
                aria-label='Undo'
                {{on 'click' this.undoLastStroke}}
              >
                <svg
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <polyline points='9 14 4 9 9 4' />
                  <path d='M20 20a8 8 0 0 0-8-8H4' />
                </svg>
              </button>
              <button
                class='tool-ico dl'
                title='Download PNG'
                aria-label='Download PNG'
                {{on 'click' this.downloadPNG}}
              >
                <svg
                  viewBox='0 0 24 24'
                  fill='none'
                  stroke='currentColor'
                  stroke-width='2'
                >
                  <path d='M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4' />
                  <polyline points='7,10 12,15 17,10' />
                  <line x1='12' y1='15' x2='12' y2='3' />
                </svg>
              </button>
            </div>

          </div>

          <div class='canvas-area'>
            <div class='canvas-frame'>

              <div
                class='dot-canvas'
                {{on 'click' this.addDot}}
                {{on 'mousedown' this.startDraw}}
                {{on 'mousemove' this.moveDraw}}
                {{on 'mouseup' this.endDraw}}
                {{on 'mouseleave' this.endDraw}}
                {{on 'touchstart' this.startDraw}}
                {{on 'touchmove' this.moveDraw}}
                {{on 'touchend' this.endDraw}}
              >

                {{#each this.dots as |dot|}}
                  <div
                    class='dot'
                    style='left: {{dot.x}}%; top: {{dot.y}}%; background-color: {{dot.color}}; width: {{dot.size}}px; height: {{dot.size}}px;'
                  ></div>
                {{/each}}

                <!-- palette toggle chevron -->
                <button
                  class='palette-toggle'
                  aria-label='Toggle palette'
                  title='Toggle palette'
                  {{on 'click' this.togglePalette}}
                >
                  {{if this.showPalette '«' '»'}}
                </button>
              </div>

              {{#unless this.hasDrawn}}
                <div class='canvas-help'>
                  <p>{{if
                      this.isEraser
                      '🧽 Eraser mode - click to erase'
                      '🎨 Click & drag to paint'
                    }}</p>
                  <p>Brush: {{this.currentBrushSize}}px</p>
                </div>
              {{/unless}}

            </div>
          </div>
        </div>
      </div>

      <style scoped>
        /* ¹⁰ Complete workspace styles */
        .drawing-workspace {
          width: 100%;
          height: 100%;
          background: linear-gradient(
            135deg,
            #1e3a8a 0%,
            #7c3aed 50%,
            #be185d 100%
          );
          padding: 1.5rem;
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
          font-family:
            'Inter',
            -apple-system,
            BlinkMacSystemFont,
            sans-serif;
        }

        .workspace-header {
          background: rgba(255, 255, 255, 0.95);
          border-radius: 0.75rem;
          padding: 0.75rem 1rem; /* ³⁷ Much smaller header */
          margin-bottom: 0.75rem;
          display: flex;
          justify-content: space-between;
          align-items: center;
          backdrop-filter: blur(10px);
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.08);
        }

        .title-section {
          flex: 1;
        }

        .title-input {
          font-size: 1.125rem; /* ³⁸ Smaller title input */
          font-weight: 600;
          color: #1e293b;
          border: none;
          background: transparent;
          outline: none;
          width: 100%;
          max-width: 300px;
        }

        .title-input::placeholder {
          color: #94a3b8;
        }

        .title-input:focus {
          color: #1e40af;
        }

        .public-toggle {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-weight: 500;
          color: #374151;
          cursor: pointer;
        }

        .public-toggle input {
          width: 1.25rem;
          height: 1.25rem;
          cursor: pointer;
        }

        .main-workspace {
          flex: 1;
          display: grid;
          grid-template-columns: 180px 1fr; /* sidebar + canvas */
          gap: 0.75rem;
          min-height: 0;
        }
        .main-workspace.no-palette {
          grid-template-columns: 0px 1fr; /* collapse sidebar */
        }

        .color-panel {
          background: rgba(255, 255, 255, 0.95);
          border-radius: 0.75rem;
          padding: 1rem; /* ⁴⁰ Smaller sidebar padding */
          backdrop-filter: blur(10px);
          box-shadow: 0 4px 16px rgba(0, 0, 0, 0.08);
          height: fit-content; /* ⁴¹ Don't stretch full height */
        }

        .color-panel h3 {
          margin: 0 0 0.75rem 0;
          color: #1e293b;
          font-size: 0.875rem; /* ⁴² Smaller section headings */
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .color-grid {
          display: grid;
          grid-template-columns: repeat(3, 1fr);
          gap: 0.375rem;
          margin-bottom: 0.75rem;
        }
        .swatch {
          width: 28px;
          height: 28px;
          border-radius: 50%;
          border: 2px solid #e5e7eb;
          cursor: pointer;
          transition:
            transform 0.12s,
            box-shadow 0.12s,
            border-color 0.12s;
          display: grid;
          place-items: center;
        }
        .swatch svg {
          width: 20px; /* ⁵¹ Bigger eraser icon */
          height: 20px;
          color: #111827;
        }

        /* ⁵² Eraser gets checkerboard background */
        .swatch.eraser {
          width: 36px; /* larger than color swatches */
          height: 36px; /* larger than color swatches */
          background:
            linear-gradient(45deg, #f3f4f6 25%, transparent 25%),
            linear-gradient(-45deg, #f3f4f6 25%, transparent 25%),
            linear-gradient(45deg, transparent 75%, #f3f4f6 75%),
            linear-gradient(-45deg, transparent 75%, #f3f4f6 75%);
          background-size: 8px 8px;
          background-position:
            0 0,
            0 4px,
            4px -4px,
            -4px 0px;
        }
        .swatch.eraser svg {
          width: 24px; /* bigger icon */
          height: 24px;
        }
        .swatch:hover {
          transform: scale(1.06);
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
        }
        .swatch.selected {
          border-color: #111827;
          box-shadow: 0 0 0 3px rgba(17, 24, 39, 0.2);
        }

        .color-grid button {
          padding: 0.5rem; /* ⁴⁴ Smaller color buttons */
          border: 2px solid #e5e7eb;
          border-radius: 0.5rem;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s;
          color: white;
          text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
          font-size: 0.75rem;
        }

        .color-grid button:hover {
          transform: translateY(-2px);
          box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
        }

        .color-grid button.selected {
          border-color: #1e293b;
          transform: scale(1.05);
          box-shadow: 0 0 0 3px rgba(30, 41, 59, 0.3);
        }

        .color-red {
          background-color: #ef4444;
        }
        .color-blue {
          background-color: #3b82f6;
        }
        .color-green {
          background-color: #22c55e;
        }
        .color-purple {
          background-color: #8b5cf6;
        }
        .color-orange {
          background-color: #f97316;
        }
        .color-pink {
          background-color: #ec4899;
        }

        /* ⁴⁵ Add brush size section after colors */
        .brush-section {
          margin-bottom: 1rem;
        }

        .brush-section h3 {
          margin: 0 0 0.75rem 0;
          color: #1e293b;
          font-size: 0.875rem;
          font-weight: 600;
          text-transform: uppercase;
          letter-spacing: 0.05em;
        }

        .brush-sizes {
          display: grid;
          grid-template-columns: repeat(4, 1fr);
          gap: 0.375rem;
          margin-bottom: 0.75rem;
        }

        /* Compact tools row inside the palette panel */
        .panel-tools {
          display: flex;
          gap: 0.375rem;
          justify-content: space-between;
          margin-top: 0.5rem;
        }
        .panel-tools .tool-ico {
          background: #374151;
          color: white;
          border: none;
          border-radius: 0.375rem;
          width: 32px;
          height: 32px;
          display: grid;
          place-items: center;
          cursor: pointer;
          transition:
            background 0.12s,
            transform 0.08s;
        }
        .panel-tools .tool-ico:hover {
          background: #111827;
        }
        .panel-tools .tool-ico:active {
          transform: scale(0.98);
        }
        .panel-tools .tool-ico.dl {
          background: #10b981;
        }
        .panel-tools .tool-ico.dl:hover {
          background: #059669;
        }
        .panel-tools .tool-ico svg {
          width: 16px;
          height: 16px;
        }
        .brush-dot-btn {
          padding: 6px;
          border: 1px solid #d1d5db;
          border-radius: 8px;
          background: white;
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          transition:
            border-color 0.12s,
            background 0.12s,
            transform 0.12s;
        }
        .brush-dot-btn:hover {
          border-color: #667eea;
          background: #f0f4ff;
        }
        .brush-dot-btn.active {
          border-color: #667eea;
          background: #667eea1a;
        }
        .dot-demo {
          display: inline-block;
          border-radius: 50%;
          background: #111827;
        }

        .eraser-btn {
          width: 100%;
          padding: 0.5rem;
          border: 2px solid #ef4444;
          border-radius: 0.5rem;
          background: white;
          color: #ef4444;
          font-weight: 600;
          cursor: pointer;
          transition: all 0.2s;
          font-size: 0.75rem;
          margin-bottom: 1rem;
        }

        .eraser-btn:hover {
          background: #ef4444;
          color: white;
        }

        .eraser-btn.active {
          background: #ef4444;
          color: white;
          transform: scale(0.98);
        }

        .selected-display {
          background: #f8fafc;
          border-radius: 0.5rem;
          padding: 0.75rem; /* ⁴⁶ Smaller selected color display */
          text-align: center;
        }

        .selected-display p {
          margin: 0 0 0.375rem 0;
          font-weight: 500;
          color: #374151;
          font-size: 0.75rem;
        }

        .color-swatch {
          width: 2rem; /* ⁴⁷ Smaller color swatch */
          height: 2rem;
          border-radius: 50%;
          margin: 0 auto 0.375rem;
          border: 2px solid white;
          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        .selected-display code {
          background: #e2e8f0;
          padding: 0.1875rem 0.375rem;
          border-radius: 0.25rem;
          font-family: 'JetBrains Mono', monospace;
          color: #1e293b;
          font-size: 0.6875rem;
        }

        .canvas-area {
          background: rgba(255, 255, 255, 0.95);
          border-radius: 1rem;
          backdrop-filter: blur(10px);
          box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
          overflow: hidden;
        }

        .canvas-frame {
          position: relative; /* for overlays */
          width: 100%;
          height: 100%;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 2rem;
          box-sizing: border-box;
        }

        .canvas-help {
          position: absolute;
          bottom: 1rem;
          left: 50%;
          transform: translateX(-50%);
          text-align: center;
          color: #64748b;
          background: rgba(255, 255, 255, 0.9);
          padding: 0.5rem 1rem;
          border-radius: 0.5rem;
          font-size: 0.75rem;
          pointer-events: none;
          backdrop-filter: blur(5px);
        }

        .canvas-help p {
          margin: 0.125rem 0;
        }

        /* Canvas controls */
        .canvas-toolbar {
          display: flex;
          gap: 0.5rem;
          justify-content: flex-end;
          width: 100%;
          margin-bottom: 0.5rem;
        }

        .tool-btn {
          background: #374151;
          color: white;
          border: none;
          border-radius: 0.5rem;
          padding: 0.5rem 0.75rem;
          font-size: 0.8125rem;
          font-weight: 600;
          cursor: pointer;
          transition:
            background 0.2s,
            transform 0.1s;
        }

        .tool-btn:hover {
          background: #111827;
        }

        .download-btn {
          background: #10b981 !important;
          display: flex;
          align-items: center;
          gap: 0.25rem;
        }

        .download-btn:hover {
          background: #059669 !important;
        }

        .btn-icon {
          width: 0.875rem;
          height: 0.875rem;
        }

        .eraser-preview {
          background: #f3f4f6;
          color: #6b7280;
          padding: 0.5rem;
          border-radius: 0.375rem;
          font-weight: 600;
          font-size: 0.75rem;
          border: 2px dashed #d1d5db;
        }

        /* Click-to-draw surface */
        .dot-canvas {
          position: relative;
          width: 100%;
          height: clamp(600px, 75vh, 1100px);
          background: white;
          border-radius: 0.75rem;
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
          margin-bottom: 0.75rem;
          overflow: hidden;
          cursor: crosshair;
        }

        .tool-ico {
          background: rgba(17, 24, 39, 0.9);
          color: white;
          border: none;
          border-radius: 0.375rem;
          width: 32px;
          height: 32px;
          display: grid;
          place-items: center;
          cursor: pointer;
          transition:
            background 0.12s,
            transform 0.08s;
        }
        .tool-ico:hover {
          background: rgba(17, 24, 39, 1);
        }
        .tool-ico:active {
          transform: scale(0.98);
        }
        .tool-ico svg {
          width: 16px;
          height: 16px;
        }
        .tool-ico.dl {
          background: #10b981;
        }
        .tool-ico.dl:hover {
          background: #059669;
        }

        /* palette toggle chevron */
        .palette-toggle {
          position: absolute;
          left: 0.5rem;
          top: 50%;
          transform: translateY(-50%);
          z-index: 2;
          width: 28px;
          height: 28px;
          border-radius: 999px;
          border: 1px solid #e5e7eb;
          background: rgba(255, 255, 255, 0.9);
          color: #111827;
          cursor: pointer;
          display: grid;
          place-items: center;
          font-weight: 700;
        }

        /* gallery caption */
        .art-caption {
          text-align: center;
          margin-top: 0.25rem;
        }
        .art-title {
          display: inline-block;
          font-size: 0.8125rem;
          letter-spacing: 0.08em;
          text-transform: uppercase;
          color: #475569;
          background: rgba(255, 255, 255, 0.8);
          padding: 0.25rem 0.5rem;
          border-radius: 0.25rem;
          border: 1px solid #e2e8f0;
        }

        .dot {
          position: absolute;
          border-radius: 50%;
          transform: translate(-50%, -50%);
          box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
          pointer-events: none; /* let clicks pass through to the canvas */
        }

        @media (max-width: 768px) {
          .main-workspace {
            grid-template-columns: 1fr;
            gap: 1rem;
          }

          .workspace-header {
            flex-direction: column;
            gap: 1rem;
            text-align: center;
          }

          .color-grid {
            grid-template-columns: repeat(3, 1fr);
          }
        }
      </style>
    </template>
  };

  static atom = class Atom extends Component<typeof SimpleDrawing> {
    <template>
      <span class='atom-title'>{{if
          @model.artworkTitle
          @model.artworkTitle
          'Untitled Drawing'
        }}</span>
      <style scoped>
        .atom-title {
          font-weight: 600;
        }
      </style>
    </template>
  };

  static embedded = class Embedded extends Component<typeof SimpleDrawing> {
    // ¹¹ Embedded format
    <template>
      <div class='drawing-preview'>
        <div class='preview-header'>
          {{#if @model.cardThumbnailURL}}
            <div class='thumbnail-preview'>
              <img src={{@model.cardThumbnailURL}} alt='Drawing preview' />
            </div>
          {{else}}
            <div class='preview-icon'>
              <svg
                viewBox='0 0 24 24'
                fill='none'
                stroke='currentColor'
                stroke-width='2'
              >
                <circle cx='12' cy='12' r='10' stroke='#667eea' />
                <circle cx='12' cy='12' r='6' stroke='#8b5cf6' />
                <circle cx='12' cy='12' r='2' fill='#ec4899' />
              </svg>
            </div>
          {{/if}}
          <div class='preview-info'>
            <h3>{{if
                @model.artworkTitle
                @model.artworkTitle
                'Untitled Drawing'
              }}</h3>

          </div>
        </div>
      </div>

      <style scoped>
        /* ¹² Embedded styles */
        .drawing-preview {
          background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
          border-radius: 0.75rem;
          padding: 1.5rem;
          border: 1px solid #e2e8f0;
        }

        .preview-header {
          display: flex;
          flex-direction: column;
          gap: 0.75rem;
        }

        .preview-icon {
          width: 3rem;
          height: 3rem;
          flex-shrink: 0;
        }

        .preview-icon svg {
          width: 100%;
          height: 100%;
        }

        /* ⁵³ Thumbnail styles for embedded */
        .thumbnail-preview {
          width: 100%;
          height: 10rem;
          border-radius: 0.5rem;
          overflow: hidden;
          border: 1px solid #e2e8f0;
        }

        .thumbnail-preview img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        .preview-info {
          flex: 1;
        }

        .preview-info h3 {
          margin: 0 0 0.25rem 0;
          color: #1e293b;
          font-weight: 600;
          font-size: 1.125rem;
        }

        .preview-info p {
          margin: 0 0 0.5rem 0;
          color: #64748b;
          font-size: 0.875rem;
        }

        .color-info {
          display: flex;
          align-items: center;
          gap: 0.5rem;
          font-size: 0.75rem;
          color: #6b7280;
          font-family: 'JetBrains Mono', monospace;
        }

        .color-dot {
          width: 1rem;
          height: 1rem;
          border-radius: 50%;
          border: 1px solid rgba(0, 0, 0, 0.1);
        }
      </style>
    </template>
  };

  static fitted = class Fitted extends Component<typeof SimpleDrawing> {
    // ¹³ Fitted format
    <template>
      <div class='fitted-card'>
        {{#if @model.cardThumbnailURL}}
          <div class='fitted-thumbnail'>
            <img src={{@model.cardThumbnailURL}} alt='Drawing' />
          </div>
          <div class='fitted-caption'>
            {{if @model.artworkTitle @model.artworkTitle 'Untitled Drawing'}}
          </div>
        {{else}}
          <div class='fitted-icon'>
            <svg
              viewBox='0 0 24 24'
              fill='none'
              stroke='currentColor'
              stroke-width='2'
            >
              <circle cx='12' cy='12' r='10' />
              <circle cx='12' cy='12' r='6' />
              <circle cx='12' cy='12' r='2' fill='currentColor' />
            </svg>
          </div>
        {{/if}}
        <div class='fitted-text'>
          <span>{{if @model.artworkTitle @model.artworkTitle 'Drawing'}}</span>
          {{#if @model.selectedColor}}
            <div
              class='fitted-color'
              style='background-color: {{@model.selectedColor}};'
            ></div>
          {{/if}}
        </div>
      </div>

      <style scoped>
        /* ¹⁴ Fitted styles */
        .fitted-card {
          width: 100%;
          height: 100%;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          border-radius: 0.5rem;
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
          color: white;
          padding: 1rem;
          box-sizing: border-box;
          position: relative;
        }
        /* When a thumbnail is present, let it fill and hide the text block */
        .fitted-card:has(.fitted-thumbnail) {
          padding: 0.25rem;
        }
        .fitted-card:has(.fitted-thumbnail) .fitted-text {
          display: none;
        }

        .fitted-icon {
          width: 2rem;
          height: 2rem;
          flex-shrink: 0;
        }
        .fitted-thumbnail {
          width: 100%;
          height: 100%;
          border-radius: 0.25rem;
          overflow: hidden;
          border: 1px solid rgba(255, 255, 255, 0.2);
        }

        .fitted-icon svg {
          width: 100%;
          height: 100%;
        }

        /* ⁵⁴ Fitted thumbnail styles */
        .fitted-thumbnail {
          border-radius: 0.25rem;
          overflow: hidden;
          border: 1px solid rgba(255, 255, 255, 0.2);
        }

        .fitted-thumbnail img {
          width: 100%;
          height: 100%;
          object-fit: cover;
        }

        /* Small caption over image for gallery feel */
        .fitted-caption {
          position: absolute;
          left: 50%;
          bottom: 0.5rem;
          transform: translateX(-50%);
          background: rgba(0, 0, 0, 0.55);
          color: white;
          font-size: 0.7rem;
          padding: 0.125rem 0.375rem;
          border-radius: 0.25rem;
          max-width: 90%;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          text-align: center;
        }

        .fitted-text {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 0.25rem;
        }

        .fitted-text span {
          font-weight: 600;
          font-size: 0.875rem;
        }

        .fitted-color {
          width: 0.75rem;
          height: 0.75rem;
          border-radius: 50%;
          border: 1px solid rgba(255, 255, 255, 0.5);
        }
      </style>
    </template>
  };

  static edit = class Edit extends Component<typeof SimpleDrawing> {
    // ¹⁵ Edit format
    <template>
      <div class='edit-form'>
        <div class='form-section'>
          <label class='form-label'>
            Artwork Title
            <input
              type='text'
              class='text-input'
              value={{@model.artworkTitle}}
              placeholder='Enter your drawing title...'
              {{on 'input' (fn @set 'artworkTitle')}}
            />
          </label>
        </div>

        <div class='form-section'>
          <label class='checkbox-label'>
            <input
              type='checkbox'
              class='checkbox-input'
              checked={{@model.isPublic}}
              {{on 'change' (fn @set 'isPublic')}}
            />
            Make this drawing publicly visible
          </label>
        </div>

        {{#if @model.selectedColor}}
          <div class='form-section'>
            <div class='current-color'>
              <p>Current brush color:</p>
              <div class='color-display'>
                <div
                  class='color-circle'
                  style='background-color: {{@model.selectedColor}};'
                ></div>
                <code>{{@model.selectedColor}}</code>
              </div>
            </div>
          </div>
        {{/if}}
      </div>

      <style scoped>
        /* ¹⁶ Edit form styles */
        .edit-form {
          padding: 1.5rem;
          background: linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%);
          min-height: 300px;
        }

        .form-section {
          margin-bottom: 1.5rem;
        }

        .form-label {
          display: flex;
          flex-direction: column;
          gap: 0.5rem;
          font-weight: 600;
          color: #374151;
        }

        .text-input {
          padding: 0.875rem;
          border: 2px solid #d1d5db;
          border-radius: 0.5rem;
          font-size: 1rem;
          transition: border-color 0.2s;
        }

        .text-input:focus {
          outline: none;
          border-color: #667eea;
          box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }

        .checkbox-label {
          display: flex;
          align-items: center;
          gap: 0.75rem;
          font-weight: 500;
          color: #374151;
          cursor: pointer;
        }

        .checkbox-input {
          width: 1.25rem;
          height: 1.25rem;
          cursor: pointer;
        }

        .current-color {
          background: white;
          border-radius: 0.75rem;
          padding: 1rem;
          text-align: center;
        }

        .current-color p {
          margin: 0 0 0.75rem 0;
          font-weight: 500;
          color: #374151;
        }

        .color-display {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 0.75rem;
        }

        .color-circle {
          width: 2rem;
          height: 2rem;
          border-radius: 50%;
          border: 2px solid #e5e7eb;
          box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        }

        code {
          background: #f1f5f9;
          padding: 0.375rem 0.75rem;
          border-radius: 0.375rem;
          font-family: 'JetBrains Mono', monospace;
          color: #1e293b;
          font-weight: 500;
        }
      </style>
    </template>
  };
}
