// @license magnet:?xt=urn:btih:d3d9a9a6595521f9666a5e94cc830dab83b65699&dn=expat.txt Expat

// Makes each .image-slider draggable (mouse, touch, pen) and keyboard
// operable, replacing the CSS resize fallback by setting its --pos split.
(function () {
    const KEY_STEPS_PERCENT = { ArrowLeft: -5, ArrowRight: 5, ArrowDown: -5, ArrowUp: 5 };
    const TOUCH_SLOP_PX = 8;
    function enhanceImageSlider(slider) {
        let positionPercent = 50;
        let touchOriginX = null;
        const setPosition = percent => {
            positionPercent = Math.min(100, Math.max(0, percent));
            slider.style.setProperty('--pos', positionPercent + '%');
            slider.setAttribute('aria-valuenow', Math.round(positionPercent));
        };
        const percentAt = event => {
            const rect = slider.getBoundingClientRect();
            return 100 * (event.clientX - rect.left) / rect.width;
        };
        slider.setAttribute('role', 'slider');
        slider.setAttribute('tabindex', '0');
        slider.setAttribute('aria-valuemin', '0');
        slider.setAttribute('aria-valuemax', '100');
        if (!slider.hasAttribute('aria-label'))
            slider.setAttribute('aria-label', 'Comparison split (percent of left image shown)');
        setPosition(positionPercent);
        slider.addEventListener('pointerdown', event => {
            if (event.button !== 0) return;
            event.preventDefault(); // no native image drag or text selection
            slider.setPointerCapture(event.pointerId);
            // A touch may yet become a vertical scroll (pointercancel), so it
            // only moves the split on release or a clear horizontal drag.
            if (event.pointerType === 'touch') touchOriginX = event.clientX;
            else setPosition(percentAt(event));
        });
        slider.addEventListener('pointermove', event => {
            if (!slider.hasPointerCapture(event.pointerId)) return;
            if (touchOriginX !== null && Math.abs(event.clientX - touchOriginX) < TOUCH_SLOP_PX) return;
            touchOriginX = null;
            setPosition(percentAt(event));
        });
        slider.addEventListener('pointerup', event => {
            if (slider.hasPointerCapture(event.pointerId)) setPosition(percentAt(event));
        });
        slider.addEventListener('keydown', event => {
            const step = KEY_STEPS_PERCENT[event.key];
            if (step !== undefined) setPosition(positionPercent + (event.shiftKey ? step / 5 : step));
            else if (event.key === 'Home') setPosition(0);
            else if (event.key === 'End') setPosition(100);
            else return;
            event.preventDefault();
        });
    }
    document.querySelectorAll('.image-slider').forEach(enhanceImageSlider);
})();

// @license-end
