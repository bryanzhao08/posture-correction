// FormCoach pitch deck. Look: the user's Slidesgo template (deep green, gold Bodoni headings).
// Structure: investor narrative modelled on the user's "Transient" reference deck.
// Build: PPTX_SKILL=<pptx skill dir> node build_deck.js  ->  FormCoach_Pitch.pptx
const pptxgen = require("pptxgenjs");
const React = require("react");
const ReactDOMServer = require("react-dom/server");
const sharp = require("sharp");
const fa = require("react-icons/fa6");
const { applyTheme } = require(process.env.PPTX_SKILL + "/scripts/apply_theme.js");

const A = (f) => `${__dirname}/assets/${f}`;
const OUT = `${__dirname}/FormCoach_Pitch.pptx`;

const THEME = {
  name: "FormCoach Emerald",
  headFontFace: "Bodoni Moda",
  bodyFontFace: "Arial",
  colors: {
    dk1: "FFFFFF", // body text (the deck is dark, so text is the light colour)
    lt1: "04231F", // slide background green
    dk2: "C4AB84", // gold: headings and accents
    lt2: "0B3A33", // lighter green for cards
    accent1: "C4AB84",
    accent2: "E9DCC4",
    accent3: "6FA592",
    accent4: "E35D5D",
    accent5: "8FB8A8",
    accent6: "F2E3B3",
    hlink: "E9DCC4",
    folHlink: "C4AB84",
  },
};
const HEX = THEME.colors;

// Pricing chosen by the user: one plan, three ways to pay.
const PRICE = { monthly: 4.99, annual: 39.99, lifetime: 99.99 };
const PLAYERS_M = 48.1 + 27.3 + 24.3; // US golf + tennis + pickleball players, millions (NGF, SFIA 2025)

async function icon(Comp, color) {
  const svg = ReactDOMServer.renderToStaticMarkup(React.createElement(Comp, { color: `#${color}`, size: 256 }));
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  return "image/png;base64," + png.toString("base64");
}

(async () => {
  const pres = new pptxgen();
  pres.layout = "LAYOUT_16x9"; // 10 x 5.625 in
  pres.title = "FormCoach";
  pres.author = "FormCoach";
  pres.theme = { headFontFace: THEME.headFontFace, bodyFontFace: THEME.bodyFontFace };
  const C = pres.SchemeColor;

  // ---------- layouts ----------
  const rule = { line: { x: 0.65, y: 5.12, w: 8.7, h: 0, line: { color: C.text2, width: 0.75 } } };
  const num = { x: 9.05, y: 5.2, w: 0.4, h: 0.3, fontSize: 10, color: C.text2, align: "right" };
  pres.defineSlideMaster({
    title: "FC Title",
    background: { path: A("bg_green.png") },
    objects: [
      { image: { x: 4.6, y: 3.3, w: 2.6, h: 2.6, path: A("sunburst.png") } },
      { image: { x: 0.35, y: 0.25, w: 0.45, h: 0.45, path: A("sparkle.png") } },
      rule,
      { placeholder: { options: { name: "title", type: "title", x: 0.7, y: 1.45, w: 4.2, h: 1.5, fontSize: 50, color: C.text2, valign: "bottom", align: "left", margin: 0 }, text: "" } },
      { placeholder: { options: { name: "body", type: "body", x: 0.7, y: 3.15, w: 3.4, h: 0.5, fontSize: 14, bold: true, color: C.text1, margin: 0 }, text: "" } },
    ],
  });
  pres.defineSlideMaster({
    title: "FC Content",
    background: { path: A("bg_green.png") },
    objects: [
      { image: { x: -0.75, y: -0.75, w: 1.5, h: 1.5, path: A("sunburst.png") } },
      { image: { x: 9.15, y: 0.35, w: 0.4, h: 0.4, path: A("sparkle.png") } },
      rule,
      { placeholder: { options: { name: "kicker", type: "body", x: 0.7, y: 0.3, w: 8.2, h: 0.25, fontSize: 10, bold: true, charSpacing: 2, color: C.text2, margin: 0 }, text: "" } },
      { placeholder: { options: { name: "title", type: "title", x: 0.7, y: 0.55, w: 8.3, h: 0.7, fontSize: 28, color: C.text2, valign: "middle", align: "left", margin: 0 }, text: "" } },
    ],
    slideNumber: num,
  });
  pres.defineSlideMaster({
    title: "FC Statement",
    background: { path: A("bg_green.png") },
    objects: [
      { image: { x: 8.3, y: 3.3, w: 2.6, h: 2.6, path: A("sunburst.png") } },
      { image: { x: 0.45, y: 0.4, w: 0.45, h: 0.45, path: A("sparkle.png") } },
      rule,
      { placeholder: { options: { name: "kicker", type: "body", x: 0.95, y: 1.0, w: 8, h: 0.4, fontSize: 12, bold: true, charSpacing: 2, color: C.text2, margin: 0 }, text: "" } },
      { placeholder: { options: { name: "statement", type: "body", x: 0.95, y: 1.5, w: 7.6, h: 2.6, fontSize: 26, bold: true, color: C.text1, valign: "top", margin: 0 }, text: "" } },
    ],
    slideNumber: num,
  });

  const phone = (slide, name, x, y, h, label) => {
    const w = h * (632 / 1335);
    slide.addImage({ path: A(`phone_${name}.png`), x, y, w, h, objectName: `Phone ${name}`, altText: label });
    return w;
  };
  const body = (text, opts) => ({ text, options: { breakLine: true, ...opts } });
  const content = (section, kicker, title) => {
    const sl = pres.addSlide({ masterName: "FC Content", sectionTitle: section });
    sl.addText(kicker.toUpperCase(), { placeholder: "kicker" });
    sl.addText(title, { placeholder: "title" });
    return sl;
  };
  const card = (sl, x, y, w, h, name, highlight = false) =>
    sl.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x, y, w, h, rectRadius: 0.1, objectName: name,
      fill: { color: highlight ? C.text2 : C.background2 }, line: { color: C.text2, width: 1 },
    });
  const text = (sl, runs, o) => sl.addText(runs, { margin: 0, valign: "top", color: C.text1, isTextBox: true, ...o });

  // ---------- 1. Title ----------
  pres.addSection({ title: "Introduction" });
  let s = pres.addSlide({ masterName: "FC Title", sectionTitle: "Introduction" });
  s.addText("FormCoach", { placeholder: "title" });
  s.addText("What's FormCoach?", { placeholder: "body" });
  s.addImage({ path: A("arch_session.png"), x: 5.05, y: 0.45, w: 2.85, h: 3.7, objectName: "Hero arch", altText: "FormCoach counting a golf swing live" });
  s.addNotes("FormCoach: an iPhone app that coaches golf, basketball, tennis and pickleball from a phone on a tripod.");

  // ---------- 2. One-line pitch ----------
  s = pres.addSlide({ masterName: "FC Statement", sectionTitle: "Introduction" });
  s.addText("THE PITCH", { placeholder: "kicker" });
  s.addText("“Your coach on a tripod: it counts every real rep, scores it against the pros, and shows you exactly how to fix it.”", { placeholder: "statement" });

  // ---------- 3. Problem ----------
  s = content("Introduction", "The problem", "Introducing the Future of Practice…");
  text(s, [
    body("How many hours have you spent practising alone, repeating the same flaw without knowing it?", { fontSize: 15, bold: true, paraSpaceAfter: 10 }),
    body("Most practice happens with no coach in sight. You can't see your own form, and your phone's camera roll is full of swings nobody ever analyses.", { fontSize: 14, paraSpaceAfter: 10 }),
    body("The apps that try to help each cover one sport, and most leave you to film, trim and review the clips yourself.", { fontSize: 14, paraSpaceAfter: 10 }),
    { text: "We asked a simpler question: what if your phone could just watch, count the reps that matter, and tell you what to fix?", options: { fontSize: 14, bold: true } },
  ], { x: 0.7, y: 1.45, w: 5.6, h: 3.4, objectName: "Problem narrative" });
  phone(s, "home", 7.0, 1.25, 3.7, "FormCoach home screen with four sports");

  // ---------- 4. The gap ----------
  s = content("Introduction", "The gap", "Most practice happens with nobody watching");
  const gaps = [
    ["You can't see yourself", "Form breaks down in ways you cannot feel. Without video and analysis, the same flaw gets grooved rep after rep."],
    ["Coaching is occasional", "A lesson gives a few fixes. The hours of practice in between go unchecked, and nobody counts the reps that were done right."],
    ["Tools are fragmented", "Each AI coaching app covers one sport. A family that golfs, plays pickleball and shoots hoops needs several subscriptions."],
  ];
  gaps.forEach(([h, t], i) => {
    const x = 0.7 + i * 2.95;
    card(s, x, 1.55, 2.7, 2.75, `Gap card ${i + 1}`);
    text(s, [
      { text: `0${i + 1}`, options: { fontSize: 12, bold: true, color: C.text2, breakLine: true, paraSpaceAfter: 6 } },
      { text: h, options: { fontFace: THEME.headFontFace, fontSize: 18, color: C.text2, breakLine: true, paraSpaceAfter: 8 } },
      { text: t, options: { fontSize: 13 } },
    ], { x: x + 0.2, y: 1.72, w: 2.3, h: 2.45, objectName: `Gap text ${i + 1}` });
  });
  text(s, "The missing piece is a coach that is always there during practice.", { x: 0.7, y: 4.55, w: 8.6, h: 0.35, fontSize: 13, italic: true, color: C.text2 });

  // ---------- 5. How it works ----------
  pres.addSection({ title: "Product" });
  s = content("Product", "Product architecture", "How does FormCoach work?");
  const steps = [
    [fa.FaCameraRetro, "Prop it up", "Phone on a tripod, facing you. The app checks your whole body is in frame."],
    [fa.FaPersonRunning, "Track", "Apple Vision follows 13 body joints, live and on-device. No video leaves the phone."],
    [fa.FaCheckDouble, "Count", "A state machine counts only real swings and shots, never waggles, dribbles or stretches."],
    [fa.FaRankingStar, "Score", "Every rep is scored 0–100 against ranges fitted on real pros and athletes."],
    [fa.FaChartLine, "Coach", "A cue per rep, a 3D demo of the fix, and progress emails every 5 sessions."],
  ];
  for (let i = 0; i < steps.length; i++) {
    const [Ic, head, txt] = steps[i];
    const x = 0.7 + i * 1.76;
    s.addShape(pres.shapes.OVAL, { x: x + 0.38, y: 1.55, w: 0.78, h: 0.78, fill: { color: C.background2 }, line: { color: C.text2, width: 1 }, objectName: `Step ${i + 1} badge` });
    s.addImage({ data: await icon(Ic, HEX.dk2), x: x + 0.58, y: 1.75, w: 0.38, h: 0.38, objectName: `Step ${i + 1} icon`, altText: head });
    text(s, `0${i + 1}`, { x, y: 2.47, w: 1.55, h: 0.3, fontSize: 12, color: C.text2, align: "center" });
    text(s, head, { x, y: 2.77, w: 1.55, h: 0.4, fontFace: THEME.headFontFace, fontSize: 18, color: C.text2, align: "center" });
    text(s, txt, { x, y: 3.22, w: 1.55, h: 1.6, fontSize: 11.5, align: "center" });
  }

  // ---------- 6-9. Key features ----------
  const feature = (title, bullets, phones, bh = 3.35) => {
    const sl = content("Product", "Key feature", title);
    sl.addText(bullets.map((b, i) => ({ text: b, options: { bullet: { code: "25C6" }, breakLine: i < bullets.length - 1, paraSpaceAfter: 12 } })),
      { x: 0.7, y: 1.5, w: 4.3, h: bh, fontSize: 14, color: C.text1, valign: "top", margin: 0, objectName: "Feature points" });
    let x = 5.45;
    for (const [name, alt] of phones) { x += phone(sl, name, x, 1.2, 3.8, alt) + 0.3; }
    return sl;
  };
  feature("Counts Only Real Reps", [
    "Golf swings, jump shots, forehands, backhands, serves and dinks, detected automatically",
    "Waggles, dribbles, walking, stretching and lowering the arms are ignored, and the app shows how many motions it skipped and why",
    "97% of held-out pro golf swings detected; 98% of free throws counted exactly once, with zero double counts",
  ], [["session", "Live golf session counting reps"], ["tennis", "Tennis session counting forehand, backhand and serve"]]);
  feature("Scored Against the Pros", [
    "Every rep gets a 0–100 score per metric: tempo, lead arm, head sway, release height, swing-through…",
    "Reference ranges were fitted on pro and athlete data, then checked on data the fit never saw",
    "Session score = 85% form + 15% consistency, with the top fixes listed first",
  ], [["summary", "Session summary with score and coaching focus"], ["summary2", "Metrics against professional targets"]]);
  feature("See the Fix in 3D", [
    "Every coaching cue asks first: “Want to see what this means?”",
    "A 3D hologram plays the wrong movement, then the correct one, in sync",
    "40 demos across all four sports, including how to set up the tripod",
  ], [["holo_wrong", "Hologram showing the wrong movement"], ["holo_correct", "Hologram showing the correct movement"]]);
  s = feature("Progress That Follows You", [
    "Sessions save on the phone first, then sync, so practice works offline",
    "Each session is compared with your own previous average",
    "Every 5 sessions, a checkpoint email compares the block with the last one",
  ], [["history", "Score history and statistics"]], 1.95);
  card(s, 0.7, 3.55, 4.3, 1.15, "Email card");
  text(s, [
    { text: "Checkpoint email", options: { fontSize: 11, color: C.text2, bold: true, breakLine: true } },
    { text: "Block average 88 → 94", options: { fontSize: 13, bold: true, breakLine: true } },
    { text: "Focus next: rotate your back to the target", options: { fontSize: 10.5 } },
  ], { x: 0.88, y: 3.65, w: 3.95, h: 0.95, objectName: "Email card text" });

  // ---------- 10. Validation ----------
  pres.addSection({ title: "Evidence" });
  s = content("Evidence", "Validation", "Validated on Real Data");
  const stats = [["1,800+", "real swings and shots tested across golf, tennis and basketball"], ["97%", "of held-out pro golf swings detected; impact timed to the frame"], ["98%", "of held-out free throws counted exactly once, zero double counts"]];
  stats.forEach(([n, l], i) => {
    const x = 0.7 + i * 2.95;
    text(s, n, { x, y: 1.55, w: 2.7, h: 1.0, fontFace: THEME.headFontFace, fontSize: 54, color: C.text2, objectName: `Stat ${i + 1}` });
    text(s, l, { x, y: 2.6, w: 2.55, h: 0.8, fontSize: 13 });
  });
  text(s, "Datasets: GolfDB (pro golf), THETIS (tennis, experts vs beginners), MLSE SPL Open Data (free-throw motion capture), Penn Action (real-world clips, including movements that must not count). Fitted on training splits, verified on held-out data.",
    { x: 0.7, y: 3.9, w: 8.6, h: 0.9, fontSize: 11, italic: true, objectName: "Datasets note" });

  // ---------- 11. Opportunity ----------
  pres.addSection({ title: "Market" });
  s = content("Market", "Market opportunity", "A market of nearly 100M players");
  s.addChart(pres.charts.BAR, [{ name: "US players, 2025 (millions)", labels: ["Pickleball", "Tennis", "Golf"], values: [24.3, 27.3, 48.1] }], {
    x: 0.55, y: 1.3, w: 4.6, h: 3.55, barDir: "bar", chartColors: [HEX.dk2], showValue: true, dataLabelPosition: "outEnd",
    dataLabelFormatCode: "0.0", dataLabelColor: HEX.dk1, dataLabelFontSize: 12, dataLabelFontFace: "+mn-lt", showTitle: true,
    title: "US players in 2025 (millions)", titleColor: HEX.dk1, titleFontSize: 12, titleFontFace: "+mn-lt",
    catAxisLabelColor: HEX.dk1, catAxisLabelFontFace: "+mn-lt", catAxisLabelFontSize: 12, valAxisHidden: true,
    valGridLine: { style: "none" }, catGridLine: { style: "none" }, showLegend: false, catAxisLineShow: false,
    objectName: "Players by sport chart",
  });
  text(s, [
    { text: "Players", options: { bold: true, color: C.text2, breakLine: true } },
    { text: "Golf hit a record 48.1M Americans (29.1M on course) in 2025 [NGF]", options: { bullet: true, breakLine: true, paraSpaceAfter: 6 } },
    { text: "Tennis 27.3M and pickleball 24.3M, pickleball up 171% in 3 years [SFIA] (counts overlap)", options: { bullet: true, breakLine: true, paraSpaceAfter: 10 } },
    { text: "Money", options: { bold: true, color: C.text2, breakLine: true } },
    { text: "AI sports-coaching apps: about $1.5B in 2025, forecast $11.2B by 2036 [Fact.MR]", options: { bullet: true, breakLine: true, paraSpaceAfter: 6 } },
    { text: "Players already pay $70–$360 a year for single-sport AI coaching apps", options: { bullet: true } },
  ], { x: 5.45, y: 1.4, w: 3.95, h: 3.4, fontSize: 13, objectName: "Opportunity points" });
  text(s, "Sources: National Golf Foundation 2025; SFIA 2026 Topline Participation Report; Fact.MR AI Sports Coaching Apps Market (2026).",
    { x: 0.7, y: 4.83, w: 8.4, h: 0.25, fontSize: 8.5, italic: true });

  // ---------- 12. Competition ----------
  s = content("Market", "The competition", "Rivals cover one sport. We cover four.");
  const hdr = (t) => ({ text: t, options: { bold: true, color: HEX.dk2, fill: { color: HEX.lt2 } } });
  const fc = (t) => ({ text: t, options: { bold: true, color: HEX.lt1, fill: { color: HEX.dk2 } } });
  s.addTable([
    [hdr("App"), hdr("Sports"), hdr("Listed price"), hdr("What it needs from you")],
    ["SwingVision", "Tennis, pickleball", "$179.99 / yr", "Court-side filming, match play"],
    ["Sportsbox AI", "Golf", "Tiered subscription", "Filming each swing"],
    ["V1 Golf", "Golf", "$69.99–$359 / yr", "Recording and reviewing clips"],
    ["HomeCourt", "Basketball", "$69.99 / yr", "Drills inside the app"],
    [fc("FormCoach"), fc("Golf, basketball, tennis, pickleball"), fc("$39.99 / yr"), fc("A tripod. It counts and coaches on its own")],
  ], {
    x: 0.7, y: 1.45, w: 8.6, colW: [1.6, 2.4, 1.7, 2.9], fontSize: 12, color: HEX.dk1, fontFace: "Arial",
    border: { type: "solid", pt: 0.75, color: HEX.dk2 }, rowH: 0.42, valign: "middle", objectName: "Competitor table",
  });
  text(s, "SwingVision counts tennis and pickleball together. Prices as listed on each company's site or the App Store, 2026.", { x: 0.7, y: 4.5, w: 8.6, h: 0.3, fontSize: 9, italic: true });

  // ---------- 13. Pricing ----------
  pres.addSection({ title: "Business" });
  s = content("Business", "Pricing", "One plan, every sport, three ways to pay");
  const plans = [
    ["Monthly", `$${PRICE.monthly}`, "per month", "Try it for a season. Cancel any time.", false],
    ["Annual", `$${PRICE.annual}`, "per year", `Saves ${Math.round(100 * (1 - PRICE.annual / (PRICE.monthly * 12)))}% vs monthly. Less than any one-sport rival.`, true],
    ["Lifetime", `$${PRICE.lifetime}`, "one time", "Pay once, keep every sport and every update.", false],
  ];
  plans.forEach(([name, price, per, note, best], i) => {
    const x = 0.7 + i * 2.95;
    card(s, x, 1.5, 2.7, 2.25, `Plan ${name}`, best);
    const ink = best ? C.background1 : C.text1;
    const accent = best ? C.background1 : C.text2;
    text(s, [
      { text: best ? `${name.toUpperCase()} · BEST VALUE` : name.toUpperCase(), options: { fontSize: 11, bold: true, charSpacing: 2, color: accent, breakLine: true, paraSpaceAfter: 6 } },
      { text: price, options: { fontFace: THEME.headFontFace, fontSize: 40, color: ink, breakLine: true } },
      { text: per, options: { fontSize: 12, color: ink, breakLine: true, paraSpaceAfter: 10 } },
      { text: note, options: { fontSize: 12, color: ink } },
    ], { x: x + 0.2, y: 1.65, w: 2.3, h: 2.0, objectName: `Plan ${name} text` });
  });
  text(s, [
    { text: "Every plan includes: ", options: { bold: true, color: C.text2 } },
    { text: "all four sports · live rep counting · 0–100 scores against the pros · coaching cues · 3D “show me” demos · full history · session and checkpoint emails · neon-marker tracking" },
  ], { x: 0.7, y: 4.0, w: 8.6, h: 0.7, fontSize: 12.5, objectName: "Plan inclusions" });

  // ---------- 14. Distribution ----------
  s = content("Business", "Distribution", "A focused path to $5M ARR");
  text(s, [
    { text: "We do not need to win the whole market. ", options: { bold: true } },
    { text: `We need 125,000 annual subscribers: about 0.13% of America's ${PLAYERS_M.toFixed(0)}M golf, tennis and pickleball players.` },
  ], { x: 0.7, y: 1.35, w: 8.6, h: 0.5, fontSize: 13, objectName: "Distribution summary" });
  const steps2 = [
    ["2,500 subscribers", "Beta clubs, courts and coaches prove retention", 2500],
    ["25,000 subscribers", "Pickleball and golf communities, App Store featuring", 25000],
    ["75,000 subscribers", "Family sharing and school and club teams", 75000],
    ["125,000 subscribers", "About 0.13% of US players", 125000],
  ];
  steps2.forEach(([h, d, n], i) => {
    const x = 0.7 + i * 2.2;
    const last = i === steps2.length - 1;
    card(s, x, 2.0, 2.0, 1.85, `Milestone ${i + 1}`, last);
    const ink = last ? C.background1 : C.text1;
    const arr = n * PRICE.annual;
    const arrText = arr >= 995000 ? `$${(arr / 1e6).toFixed(arr >= 1e7 ? 0 : 1)}M ARR` : `$${Math.round(arr / 1e3)}K ARR`;
    text(s, [
      { text: h, options: { bold: true, fontSize: 13, color: last ? C.background1 : C.text2, breakLine: true, paraSpaceAfter: 6 } },
      { text: d, options: { fontSize: 11.5, color: ink, breakLine: true, paraSpaceAfter: 8 } },
      { text: arrText, options: { fontFace: THEME.headFontFace, fontSize: 20, color: ink } },
    ], { x: x + 0.15, y: 2.12, w: 1.72, h: 1.65, objectName: `Milestone ${i + 1} text` });
  });
  const blended = (2 / 3) * PRICE.annual + (1 / 3) * PRICE.monthly * 12;
  text(s, [
    { text: "Upside: ", options: { bold: true, color: C.text2 } },
    { text: `if a third of subscribers stay on monthly billing, the same 125,000 people produce about $${(125000 * blended / 1e6).toFixed(1)}M ARR. Lifetime purchases ($${PRICE.lifetime}) add one-time cash on top and are not counted as ARR.` },
  ], { x: 0.7, y: 4.1, w: 8.6, h: 0.75, fontSize: 12, objectName: "Distribution upside" });

  // ---------- 15. Why now ----------
  s = content("Business", "Why now", "The camera in every pocket can finally coach");
  const whys = [
    [fa.FaMobileScreen, "Pose tracking is built into the phone", "Apple's Vision framework tracks the human body on-device, so coaching needs no sensors, no wearables and no cloud upload."],
    [fa.FaArrowTrendUp, "Participation is at records", "Golf reached 48.1M US players in 2025, a record [NGF]. Pickleball grew 171% in three years [SFIA]."],
    [fa.FaSackDollar, "Players already pay for AI coaching", "AI sports-coaching apps are about a $1.5B market growing near 20% a year [Fact.MR], and rivals charge up to $360 a year for one sport."],
  ];
  for (let i = 0; i < whys.length; i++) {
    const [Ic, h, t] = whys[i];
    const y = 1.45 + i * 1.15;
    s.addShape(pres.shapes.OVAL, { x: 0.7, y, w: 0.7, h: 0.7, fill: { color: C.background2 }, line: { color: C.text2, width: 1 }, objectName: `Why ${i + 1} badge` });
    s.addImage({ data: await icon(Ic, HEX.dk2), x: 0.88, y: y + 0.18, w: 0.34, h: 0.34, objectName: `Why ${i + 1} icon`, altText: h });
    text(s, [
      { text: h, options: { fontFace: THEME.headFontFace, fontSize: 17, color: C.text2, breakLine: true, paraSpaceAfter: 3 } },
      { text: t, options: { fontSize: 12.5 } },
    ], { x: 1.65, y: y - 0.02, w: 7.6, h: 1.0, objectName: `Why ${i + 1} text` });
  }

  // ---------- 16. Tech stack ----------
  s = content("Business", "Implementation", "Built, tested and running on iPhone today");
  const stack = [
    ["iPhone app", "SwiftUI · AVFoundation camera · Apple Vision body pose (13 joints) · SceneKit holograms · CoreMotion tripod check · on-device, offline-first storage"],
    ["Coaching engine", "FormCore, a Swift package. Mirrors a Python reference engine and is parity-tested on 1,324 real recordings"],
    ["Backend", "FastAPI · SQLAlchemy (SQLite, Postgres-ready) · JWT auth with bcrypt · Resend for session and checkpoint emails"],
    ["Data and testing", "MediaPipe pose extraction · GolfDB, THETIS, SPL, Penn Action · 54 Python tests · 5 iOS UI tests · Swift/Python parity checks"],
  ];
  stack.forEach(([h, t], i) => {
    const x = 0.7 + (i % 2) * 4.4;
    const y = 1.45 + Math.floor(i / 2) * 1.65;
    card(s, x, y, 4.2, 1.45, `Stack ${h}`);
    text(s, [
      { text: h, options: { fontFace: THEME.headFontFace, fontSize: 17, color: C.text2, breakLine: true, paraSpaceAfter: 4 } },
      { text: t, options: { fontSize: 11.5 } },
    ], { x: x + 0.2, y: y + 0.13, w: 3.8, h: 1.2, objectName: `Stack ${h} text` });
  });

  // ---------- 17. Separation ----------
  pres.addSection({ title: "Close" });
  s = pres.addSlide({ masterName: "FC Statement", sectionTitle: "Close" });
  s.addText("SO WHAT ACTUALLY SEPARATES US?", { placeholder: "kicker" });
  s.addText("One app, four sports, one tripod. FormCoach counts only the reps that matter, proves it on real data, and shows you the fix in 3D instead of just telling you.", { placeholder: "statement" });

  // ---------- 18. The ask ----------
  s = content("Close", "The ask", "Fund the next proof points");
  text(s, "Seeking $250,000", { x: 0.7, y: 1.4, w: 8.6, h: 0.9, fontFace: THEME.headFontFace, fontSize: 52, color: C.text2, align: "center", objectName: "Ask amount" });
  text(s, "for 10% of the company", { x: 0.7, y: 2.3, w: 8.6, h: 0.4, fontSize: 16, align: "center", objectName: "Ask equity" });
  const uses = [
    ["Prove it on real players", "A closed beta with clubs, courts and coaches; real-phone validation for every sport"],
    ["Close the pickleball gap", "Collect and label the first pickleball pose dataset (protocol already written)"],
    ["Launch", "App Store release, backend hosting and the first acquisition campaigns"],
  ];
  uses.forEach(([h, t], i) => {
    const x = 0.7 + i * 2.95;
    card(s, x, 3.0, 2.7, 1.75, `Use ${i + 1}`);
    text(s, [
      { text: h, options: { bold: true, fontSize: 13, color: C.text2, breakLine: true, paraSpaceAfter: 6 } },
      { text: t, options: { fontSize: 12 } },
    ], { x: x + 0.18, y: 3.13, w: 2.34, h: 1.5, objectName: `Use ${i + 1} text` });
  });

  // ---------- 19. Demo ----------
  s = content("Close", "Demo", "See FormCoach in 60 seconds");
  s.addMedia({ type: "video", path: A("FormCoach_Promo.mp4"), cover: "data:image/png;base64," + require("fs").readFileSync(A("promo_poster.png")).toString("base64"), x: 1.6, y: 1.35, w: 6.8, h: 3.825, objectName: "Promo video" });

  // ---------- 20. Thank you ----------
  s = pres.addSlide({ masterName: "FC Title", sectionTitle: "Close" });
  s.addText("Thank You!", { placeholder: "title" });
  s.addText("Your coach on a tripod.", { placeholder: "body" });
  text(s, [
    { text: "CREDITS: ", options: { bold: true } },
    { text: "This presentation template was created by Slidesgo, and includes icons by Flaticon, and infographics & images by Freepik." },
  ], { x: 0.7, y: 4.45, w: 4.2, h: 0.5, fontSize: 9, objectName: "Template credits" });
  s.addImage({ path: A("arch_session.png"), x: 5.05, y: 0.45, w: 2.85, h: 3.7, objectName: "Closing arch", altText: "FormCoach live session" });

  await pres.writeFile({ fileName: OUT });
  await applyTheme(OUT, THEME);
  console.log("wrote", OUT);
})();
