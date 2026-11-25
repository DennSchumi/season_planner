(() => {
  "use strict";

  /* ---------- Year in footer ---------- */
  const yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = new Date().getFullYear();

  /* ---------- Sticky nav state ---------- */
  const nav = document.querySelector(".nav");
  if (nav && !document.querySelector(".legal-page")) {
    const onScroll = () => nav.classList.toggle("is-scrolled", window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
  }

  /* ---------- Mobile menu ---------- */
  const toggle = document.querySelector(".nav-toggle");
  const panel = document.querySelector(".mobile-panel");
  if (toggle && panel) {
    const closePanel = () => {
      panel.classList.remove("is-open");
      toggle.setAttribute("aria-expanded", "false");
    };
    toggle.addEventListener("click", () => {
      const open = panel.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", String(open));
    });
    panel.querySelectorAll("a").forEach((a) => a.addEventListener("click", closePanel));
  }

  /* ---------- Assign stagger index to repeated mock children ---------- */
  document
    .querySelectorAll(".mock-cal-grid, .mock-rows, .mock-doc-grid, .mock-inv-tiles")
    .forEach((group) => {
      [...group.children].forEach((child, i) => {
        if (child.classList.contains("dow")) return;
        child.style.setProperty("--i", i);
      });
    });

  /* ---------- Progress bar width from data-w ---------- */
  document.querySelectorAll(".mock-progress-fill[data-w]").forEach((el) => {
    el.style.setProperty("--w", el.dataset.w + "%");
  });

  /* ---------- Scroll reveal ---------- */
  const revealEls = document.querySelectorAll(".reveal");
  const prefersReduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  if (!("IntersectionObserver" in window) || prefersReduced) {
    revealEls.forEach((el) => el.classList.add("in-view"));
  } else {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("in-view");
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.16, rootMargin: "0px 0px -6% 0px" }
    );
    revealEls.forEach((el) => io.observe(el));
  }

  /* ---------- Subtle hero parallax ---------- */
  const heroBg = document.querySelector(".hero-bg");
  if (heroBg && !prefersReduced) {
    let ticking = false;
    window.addEventListener(
      "scroll",
      () => {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(() => {
          const y = window.scrollY;
          heroBg.style.transform = `translateY(${y * 0.12}px)`;
          ticking = false;
        });
      },
      { passive: true }
    );
  }
})();
