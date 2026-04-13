<script lang="ts">
  import { fetchNui, onNuiMessage } from '../lib/nui';

  let visible = $state(false);
  let itemName = $state('');

  // Time
  let hour = $state(12);
  let minute = $state(0);

  // Lights (6 directions)
  let lights = $state({
    front: true,
    back: false,
    left: false,
    right: false,
    top: true,
    bottom: false,
  });
  let lightIntensity = $state(5.0);
  let lightColor = $state('#ffffff');

  // Weather
  const weathers = [
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'SMOG', 'FOGGY',
    'OVERCAST', 'RAIN', 'THUNDER', 'CLEARING', 'NEUTRAL',
    'SNOW', 'BLIZZARD', 'SNOWLIGHT', 'XMAS',
  ];
  let selectedWeather = $state('EXTRASUNNY');

  onNuiMessage('screenshotStudioOpen', (data: any) => {
    visible = true;
    itemName = data.itemName || '';
  });

  onNuiMessage('screenshotStudioClose', () => {
    visible = false;
  });

  function updateTime() {
    fetchNui('studioSetTime', { hour, minute });
  }

  function toggleLight(dir: string) {
    (lights as any)[dir] = !(lights as any)[dir];
    lights = { ...lights };
    fetchNui('studioSetLights', { lights, intensity: lightIntensity, color: lightColor });
  }

  function updateLightIntensity(val: number) {
    lightIntensity = val;
    fetchNui('studioSetLights', { lights, intensity: lightIntensity, color: lightColor });
  }

  function updateLightColor(val: string) {
    lightColor = val;
    fetchNui('studioSetLights', { lights, intensity: lightIntensity, color: lightColor });
  }

  function setWeather(val: string) {
    selectedWeather = val;
    fetchNui('studioSetWeather', { weather: val });
  }

  function capture() {
    fetchNui('studioCapture', {});
  }

  function cancel() {
    fetchNui('studioCancel', {});
  }
</script>

{#if visible}
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="fixed top-4 right-4 z-[99999] pointer-events-auto" style="width: 320px; font-family: 'Bai Jamjuree', 'TeX Gyre Heros', sans-serif;">

    <!-- Card -->
    <div style="background: hsl(24, 9.8%, 10%); border: 1px solid hsl(240, 3.7%, 15.9%); border-radius: 12px; overflow: hidden; box-shadow: 0 20px 60px rgba(0,0,0,0.5);">

      <!-- Header -->
      <div style="padding: 16px 20px; border-bottom: 1px solid hsl(240, 3.7%, 15.9%); display: flex; align-items: center; justify-content: space-between;">
        <div>
          <div style="color: #f0f0f0; font-size: 15px; font-weight: 600;">Screenshot Studio</div>
          <div style="color: hsl(240, 5%, 64.9%); font-size: 11px; margin-top: 2px;">{itemName || 'No item selected'}</div>
        </div>
        <div style="display: flex; gap: 6px;">
          <button onclick={capture}
                  style="padding: 6px 14px; background: hsl(142, 70%, 45%); color: hsl(144, 80%, 10%); border: none; border-radius: 6px; font-size: 12px; font-weight: 600; cursor: pointer;">
            CAPTURE
          </button>
          <button onclick={cancel}
                  style="padding: 6px 10px; background: hsl(0, 0%, 15%); color: #999; border: 1px solid hsl(240, 3.7%, 15.9%); border-radius: 6px; font-size: 12px; cursor: pointer;">
            ESC
          </button>
        </div>
      </div>

      <!-- Time Control -->
      <div style="padding: 14px 20px; border-bottom: 1px solid hsl(240, 3.7%, 15.9%);">
        <div style="color: hsl(240, 5%, 64.9%); font-size: 10px; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Time of Day</div>
        <div style="display: flex; align-items: center; gap: 10px;">
          <input type="range" min="0" max="23" bind:value={hour}
                 oninput={updateTime}
                 style="flex: 1; accent-color: hsl(142, 70%, 45%);" />
          <span style="color: #f0f0f0; font-size: 13px; font-weight: 500; min-width: 40px; text-align: right;">
            {String(hour).padStart(2, '0')}:{String(minute).padStart(2, '0')}
          </span>
        </div>
      </div>

      <!-- Lights -->
      <div style="padding: 14px 20px; border-bottom: 1px solid hsl(240, 3.7%, 15.9%);">
        <div style="color: hsl(240, 5%, 64.9%); font-size: 10px; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 10px;">Lights</div>

        <!-- Light direction grid -->
        <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px; max-width: 160px; margin: 0 auto;">
          <div></div>
          <button onclick={() => toggleLight('top')}
                  style="height: 32px; border-radius: 6px; border: 1px solid {lights.top ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {lights.top ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {lights.top ? 'hsl(142, 70%, 45%)' : '#666'}; font-size: 10px; cursor: pointer; font-weight: 500;">
            TOP
          </button>
          <div></div>

          <button onclick={() => toggleLight('left')}
                  style="height: 32px; border-radius: 6px; border: 1px solid {lights.left ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {lights.left ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {lights.left ? 'hsl(142, 70%, 45%)' : '#666'}; font-size: 10px; cursor: pointer; font-weight: 500;">
            LEFT
          </button>
          <button onclick={() => toggleLight('front')}
                  style="height: 32px; border-radius: 6px; border: 1px solid {lights.front ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {lights.front ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {lights.front ? 'hsl(142, 70%, 45%)' : '#666'}; font-size: 10px; cursor: pointer; font-weight: 500;">
            FRONT
          </button>
          <button onclick={() => toggleLight('right')}
                  style="height: 32px; border-radius: 6px; border: 1px solid {lights.right ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {lights.right ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {lights.right ? 'hsl(142, 70%, 45%)' : '#666'}; font-size: 10px; cursor: pointer; font-weight: 500;">
            RIGHT
          </button>

          <div></div>
          <button onclick={() => toggleLight('bottom')}
                  style="height: 32px; border-radius: 6px; border: 1px solid {lights.bottom ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {lights.bottom ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {lights.bottom ? 'hsl(142, 70%, 45%)' : '#666'}; font-size: 10px; cursor: pointer; font-weight: 500;">
            BTM
          </button>
          <button onclick={() => toggleLight('back')}
                  style="height: 32px; border-radius: 6px; border: 1px solid {lights.back ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {lights.back ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {lights.back ? 'hsl(142, 70%, 45%)' : '#666'}; font-size: 10px; cursor: pointer; font-weight: 500;">
            BACK
          </button>
        </div>

        <!-- Intensity + Color -->
        <div style="display: flex; align-items: center; gap: 10px; margin-top: 10px;">
          <div style="flex: 1;">
            <div style="color: #666; font-size: 9px; margin-bottom: 3px;">Intensity</div>
            <input type="range" min="0.5" max="20" step="0.5" bind:value={lightIntensity}
                   oninput={() => updateLightIntensity(lightIntensity)}
                   style="width: 100%; accent-color: hsl(142, 70%, 45%);" />
          </div>
          <div>
            <div style="color: #666; font-size: 9px; margin-bottom: 3px;">Color</div>
            <input type="color" bind:value={lightColor}
                   oninput={() => updateLightColor(lightColor)}
                   style="width: 36px; height: 28px; border: 1px solid hsl(240, 3.7%, 15.9%); border-radius: 4px; background: none; cursor: pointer;" />
          </div>
        </div>
      </div>

      <!-- Weather -->
      <div style="padding: 14px 20px;">
        <div style="color: hsl(240, 5%, 64.9%); font-size: 10px; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px;">Weather</div>
        <div style="display: flex; flex-wrap: wrap; gap: 4px;">
          {#each weathers as w}
            <button onclick={() => setWeather(w)}
                    style="padding: 4px 8px; border-radius: 6px; border: 1px solid {selectedWeather === w ? 'hsl(142, 70%, 45%)' : 'hsl(240, 3.7%, 15.9%)'}; background: {selectedWeather === w ? 'hsla(142, 70%, 45%, 0.15)' : 'hsl(0, 0%, 15%)'}; color: {selectedWeather === w ? 'hsl(142, 70%, 45%)' : '#888'}; font-size: 9px; cursor: pointer; font-weight: 500;">
              {w}
            </button>
          {/each}
        </div>
      </div>

      <!-- Footer hint -->
      <div style="padding: 8px 20px 12px; color: #444; font-size: 9px; text-align: center;">
        Mouse: Rotate  |  Scroll: Zoom  |  ENTER or Click: Capture
      </div>
    </div>
  </div>
{/if}
