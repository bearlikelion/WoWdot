(function () {
	"use strict";

	const DATA = window.GDDOCS;
	const BUILTIN_TYPES = new Set((
		"bool int float String StringName NodePath Vector2 Vector2i Rect2 Rect2i Vector3 Vector3i " +
		"Transform2D Vector4 Vector4i Plane Quaternion AABB Basis Transform3D Projection Color RID " +
		"Callable Signal Dictionary Array PackedByteArray PackedInt32Array PackedInt64Array " +
		"PackedFloat32Array PackedFloat64Array PackedStringArray PackedVector2Array " +
		"PackedVector3Array PackedColorArray PackedVector4Array Variant"
	).split(" "));
	const FAMILY_ROOTS = { Control: "ui", Node2D: "2d", Node3D: "3d", CanvasItem: "2d", Node: "node", Resource: "res" };
	const ENGINE_ANCHOR = { method: "method", member: "property", signal: "signal", constant: "constant", annotation: "annotation", theme_item: "theme-item" };
	const SCENE_EXTENSIONS = /\.(tscn|scn)$/;
	const has = (object, key) => Object.prototype.hasOwnProperty.call(object, key);
	const esc = (value) => String(value).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
	const byText = (a, b) => a.localeCompare(b, undefined, { sensitivity: "base" });

	const content = document.getElementById("content");
	const sidebar = document.getElementById("sidebar");
	const search = document.getElementById("search");
	const scriptClasses = DATA.script_classes || {};
	const outputDir = DATA.project.output.slice(0, DATA.project.output.lastIndexOf("/") + 1);

	let showPrivate = readSetting("gddocs.showPrivate") === "1";

	// Model

	const classes = new Map();
	for (const entry of DATA.classes) {
		classes.set(entry.name, parseClass(entry));
	}

	const topByPath = new Map();
	const children = new Map();
	for (const model of classes.values()) {
		if (!model.inner) {
			topByPath.set(model.path, model.name);
		}
		if (model.inherits) {
			if (!children.has(model.inherits)) {
				children.set(model.inherits, []);
			}
			children.get(model.inherits).push(model.name);
		}
	}

	const usersByScript = new Map();
	for (const [file, scripts] of Object.entries(DATA.usage)) {
		for (const script of scripts) {
			if (!usersByScript.has(script)) {
				usersByScript.set(script, []);
			}
			usersByScript.get(script).push(file);
		}
	}

	const autoloadByScript = new Map();
	for (const autoload of DATA.autoloads) {
		const scripts = autoload.path.endsWith(".gd") ? [autoload.path] : (DATA.usage[autoload.path] || []);
		if (scripts.length === 1) {
			autoloadByScript.set(scripts[0], autoload);
		}
	}

	const guides = DATA.guides
		.map((guide) => ({ path: guide.path, markdown: guide.markdown, title: guideTitle(guide) }))
		.sort((a, b) => (a.path === "res://README.md" ? -1 : b.path === "res://README.md" ? 1 : byText(a.path, b.path)));
	const guideByPath = new Map(guides.map((guide) => [guide.path, guide]));

	function parseClass(entry) {
		const root = new DOMParser().parseFromString(entry.xml, "application/xml").documentElement;
		const list = (selector, map) => Array.from(root.querySelectorAll(selector), map);
		const common = (el) => ({
			name: el.getAttribute("name"),
			description: text(el.querySelector(":scope > description")) || text(el),
			deprecated: el.getAttribute("deprecated"),
			experimental: el.getAttribute("experimental"),
		});
		const params = (el) => Array.from(el.querySelectorAll(":scope > param"), (param) => ({
			name: param.getAttribute("name"),
			type: typeOf(param),
			default: param.getAttribute("default"),
		}));
		return {
			name: entry.name,
			path: entry.path,
			inner: outerName(entry.name) !== entry.name,
			inherits: root.getAttribute("inherits") || "",
			brief: text(root.querySelector(":scope > brief_description")),
			description: text(root.querySelector(":scope > description")),
			deprecated: root.getAttribute("deprecated"),
			experimental: root.getAttribute("experimental"),
			comments: DATA.comments[entry.name] || {},
			tutorials: list(":scope > tutorials > link", (link) => ({
				title: link.getAttribute("title") || link.textContent.trim(),
				url: link.textContent.trim(),
			})),
			members: list(":scope > members > member", (el) => Object.assign(common(el), {
				type: typeOf(el),
				default: el.getAttribute("default"),
			})),
			methods: list(":scope > methods > method", (el) => Object.assign(common(el), {
				qualifiers: el.getAttribute("qualifiers") || "",
				returns: typeOf(el.querySelector(":scope > return")),
				params: params(el),
			})),
			signals: list(":scope > signals > signal", (el) => Object.assign(common(el), { params: params(el) })),
			constants: list(":scope > constants > constant", (el) => Object.assign(common(el), {
				value: el.getAttribute("value"),
				enum: el.getAttribute("enum"),
			})),
		};
	}

	// Doc text keeps the XML indentation; strip the common leading tabs.
	function text(el) {
		if (!el || el.children.length) {
			return "";
		}
		return dedent(el.textContent);
	}

	function dedent(raw) {
		const lines = raw.replace(/^\n+/, "").replace(/\s+$/, "").split("\n");
		const indents = lines.filter((line) => line.trim()).map((line) => line.match(/^\t*/)[0].length);
		const cut = indents.length ? Math.min(...indents) : 0;
		return lines.map((line) => line.slice(cut)).join("\n");
	}

	function typeOf(el) {
		return el ? el.getAttribute("enum") || el.getAttribute("type") || "Variant" : "void";
	}

	function outerName(name) {
		if (name.startsWith('"')) {
			return name.slice(0, name.indexOf('"', 1) + 1);
		}
		return name.split(".")[0];
	}

	function displayName(name) {
		const outer = outerName(name);
		if (outer !== name) {
			return displayName(outer) + name.slice(outer.length);
		}
		if (!name.startsWith('"')) {
			return name;
		}
		const path = "res://" + name.slice(1, -1);
		const autoload = autoloadByScript.get(path);
		return autoload ? autoload.name : path.slice(path.lastIndexOf("/") + 1);
	}

	function parentOf(name) {
		const model = classes.get(name);
		return model ? model.inherits : DATA.parents[name] || "";
	}

	function ancestors(name) {
		const chain = [];
		for (let current = parentOf(name); current && chain.length < 64; current = parentOf(current)) {
			chain.push(current);
		}
		return chain;
	}

	function family(name) {
		for (let current = name, depth = 0; current && depth < 64; current = parentOf(current), depth++) {
			if (has(FAMILY_ROOTS, current)) {
				return FAMILY_ROOTS[current];
			}
		}
		return "obj";
	}

	function isEngine(name) {
		return BUILTIN_TYPES.has(name) || (has(DATA.parents, name) && !has(scriptClasses, name));
	}

	function dot(name) {
		return `<span class="dot fam-${family(name)}${classes.has(name) ? "" : " engine"}" aria-hidden="true"></span>`;
	}

	function summary(model) {
		const raw = model.brief || model.description || model.comments[""] || "";
		const plain = raw
			.replace(/\[(?:method|member|signal|constant|enum|param) ([^\]]+)\]/g, "$1")
			.replace(/\[\/?[a-z_]+(?:=[^\]]*)?\]/g, "")
			.replace(/\[([A-Za-z_][\w.]*)\]/g, "$1")
			.replace(/\s+/g, " ")
			.trim();
		const sentence = plain.match(/^(.+?[.!?])(?:\s|$)/);
		return sentence ? sentence[1] : plain;
	}

	function guideTitle(guide) {
		const heading = guide.markdown.match(/^#\s+(.+)$/m);
		return heading ? heading[1].trim() : guide.path.slice(guide.path.lastIndexOf("/") + 1).replace(/\.md$/, "");
	}

	// Links

	function classHref(name, anchor) {
		return "#/class/" + encodeURIComponent(name) + (anchor ? "/" + encodeURIComponent(anchor) : "");
	}

	function engineUrl(cls, kind, member) {
		const lower = cls.toLowerCase();
		let url = DATA.project.engine_docs + "class_" + lower + ".html";
		if (kind === "enum") {
			url += "#enum-" + lower + "-" + member.toLowerCase();
		} else if (kind) {
			url += "#class-" + lower + "-" + ENGINE_ANCHOR[kind] + "-" + member.toLowerCase().replace(/_/g, "-");
		}
		return url;
	}

	function classLink(name) {
		if (classes.has(name)) {
			return `<a class="u" href="${classHref(name)}">${esc(displayName(name))}</a>`;
		}
		if (isEngine(name)) {
			return `<a class="t external" href="${engineUrl(name)}" title="Godot class reference">${esc(name)}</a>`;
		}
		return `<span class="u">${esc(name)}</span>`;
	}

	function typeHtml(type) {
		if (type.endsWith("[]")) {
			return `<span class="t">Array</span>[${typeHtml(type.slice(0, -2))}]`;
		}
		if (type === "void") {
			return '<span class="k">void</span>';
		}
		if (classes.has(type) || isEngine(type)) {
			return classLink(type);
		}
		const cut = type.lastIndexOf(".");
		if (cut > 0) {
			const cls = type.slice(0, cut);
			const member = type.slice(cut + 1);
			if (classes.has(cls)) {
				return `<a class="u" href="${classHref(cls, "enum-" + member)}">${esc(displayName(cls) + "." + member)}</a>`;
			}
			if (isEngine(cls)) {
				return `<a class="t external" href="${engineUrl(cls, "enum", member)}">${esc(type)}</a>`;
			}
		}
		return `<span class="u">${esc(type)}</span>`;
	}

	function refLink(kind, target, owner) {
		const cut = target.lastIndexOf(".");
		const cls = cut > 0 ? target.slice(0, cut) : owner;
		const member = cut > 0 ? target.slice(cut + 1) : target;
		const label = `<code>${esc(cut > 0 ? target : member)}</code>`;
		if (classes.has(cls)) {
			return `<a href="${classHref(cls, kind + "-" + member)}">${label}</a>`;
		}
		if (isEngine(cls)) {
			return `<a class="external" href="${engineUrl(cls, kind, member)}">${label}</a>`;
		}
		return label;
	}

	// Descriptions

	// Converts the class-reference BBCode that ## comments use.
	function bbcode(source, owner) {
		const kept = [];
		const keep = (html) => "\u0000" + (kept.push(html) - 1) + "\u0000";
		let html = esc(source)
			.replace(/\[codeblocks\]([\s\S]*?)\[\/codeblocks\]/g, (_, inner) => {
				const gdscript = inner.match(/\[gdscript\]([\s\S]*?)\[\/gdscript\]/);
				return gdscript ? keep(`<pre><code>${dedent(gdscript[1])}</code></pre>`) : "";
			})
			.replace(/\[codeblock[^\]]*\]([\s\S]*?)\[\/codeblock\]/g, (_, code) => keep(`<pre><code>${dedent(code)}</code></pre>`))
			.replace(/\[code\]([\s\S]*?)\[\/code\]/g, (_, code) => keep(`<code>${code}</code>`))
			.replace(/\[url=(https?:[^\]]+)\]([\s\S]*?)\[\/url\]/g, '<a class="external" href="$1">$2</a>')
			.replace(/\[url\](https?:[^\[]+)\[\/url\]/g, '<a class="external" href="$1">$1</a>')
			.replace(/\[(\/?)(b|i|u|s|kbd)\]/g, "<$1$2>")
			.replace(/\[br\]/g, "<br>")
			.replace(/\[\/?(center|font|color|lang|font_size|opentype_features)[^\]]*\]/g, "")
			.replace(/\[(method|member|signal|constant|enum|annotation|theme_item) ([^\]\s]+)\]/g, (_, kind, target) => keep(refLink(kind, target, owner)))
			.replace(/\[param ([^\]\s]+)\]/g, '<code class="m">$1</code>')
			.replace(/\[([A-Za-z_]\w*(?:\.\w+)?)\]/g, (whole, name) => (classes.has(name) || isEngine(name) ? keep(typeHtml(name)) : whole))
			.replace(/\[lb\]/g, "[")
			.replace(/\[rb\]/g, "]");
		const restore = (value) => value.replace(/\u0000(\d+)\u0000/g, (_, index) => kept[Number(index)]);
		return html
			.split("\n")
			.filter((line) => line.trim())
			.map((line) => (/^\u0000\d+\u0000$/.test(line.trim()) && kept[Number(line.trim().slice(1, -1))].startsWith("<pre") ? restore(line) : `<p>${restore(line)}</p>`))
			.join("");
	}

	function commentHtml(comment) {
		return `<p>${esc(comment).replace(/`([^`]+)`/g, "<code>$1</code>")}</p>`;
	}

	function describe(xmlText, comment, owner) {
		if (xmlText) {
			return bbcode(xmlText, owner);
		}
		return comment ? commentHtml(comment) : "";
	}

	function notes(item) {
		let html = "";
		if (item.deprecated != null) {
			html += `<div class="note">Deprecated${item.deprecated ? ": " + esc(item.deprecated) : "."}</div>`;
		}
		if (item.experimental != null) {
			html += `<div class="note">Experimental${item.experimental ? ": " + esc(item.experimental) : "."}</div>`;
		}
		return html;
	}

	// Signatures

	function valueHtml(value) {
		if (/^-?(\d[\d_]*\.?\d*(e-?\d+)?|0x[\da-f]+|inf|nan)$/i.test(value)) {
			return `<span class="n">${esc(value)}</span>`;
		}
		if (/^(true|false|null)$/.test(value)) {
			return `<span class="k">${value}</span>`;
		}
		if (/^[&^]?["']/.test(value)) {
			return `<span class="s">${esc(value)}</span>`;
		}
		return esc(value);
	}

	const keyword = (word) => `<span class="k">${word}</span>`;

	function paramsHtml(params) {
		return params
			.map((param) => `<span class="m">${esc(param.name)}</span>: ${typeHtml(param.type)}${param.default != null ? " = " + valueHtml(param.default) : ""}`)
			.join(", ");
	}

	function methodSig(method) {
		const prefix = method.qualifiers.includes("static") ? keyword("static") + " " : "";
		return `${prefix}${keyword("func")} <span class="f">${esc(method.name)}</span>(${paramsHtml(method.params)}) -&gt; ${typeHtml(method.returns)}`;
	}

	function memberSig(member) {
		const known = member.default != null && member.default !== "<unknown>";
		return `${keyword("var")} <span class="m">${esc(member.name)}</span>: ${typeHtml(member.type)}${known ? " = " + valueHtml(member.default) : ""}`;
	}

	function signalSig(signal) {
		return `${keyword("signal")} <span class="f">${esc(signal.name)}</span>(${paramsHtml(signal.params)})`;
	}

	function constantSig(constant) {
		return `${keyword("const")} <span class="m">${esc(constant.name)}</span> = ${valueHtml(constant.value)}`;
	}

	function enumSig(name, values) {
		const lines = values.map((value) => {
			const note = value.description ? `  <span class="c"># ${esc(value.description.split("\n")[0])}</span>` : "";
			return `\t<span class="m">${esc(value.name)}</span> = ${valueHtml(value.value)},${note}`;
		});
		return `${keyword("enum")} <span class="u">${esc(name)}</span> {\n${lines.join("\n")}\n}`;
	}

	// Pages

	function renderOverview() {
		const project = DATA.project;
		const readme = guideByPath.get("res://README.md");
		const facts = [
			["Version", project.version && esc(project.version)],
			["Godot", esc(project.godot)],
			["Main scene", project.main_scene && sceneLink(project.main_scene)],
			["Built", esc(project.built)],
		].filter((fact) => fact[1]);
		let html = `<h1 class="page">${esc(project.name || "Project")}</h1>`;
		if (project.description) {
			html += `<p class="lede">${esc(project.description)}</p>`;
		}
		html += `<dl class="facts">${facts.map(([term, value]) => `<dt>${term}</dt><dd>${value}</dd>`).join("")}</dl>`;
		if (DATA.autoloads.length) {
			html += `<div class="bar">Start with the autoloads <span class="count">${DATA.autoloads.length}</span></div><div class="rows">`;
			html += DATA.autoloads.map((autoload) => {
				const doc = docForPath(autoload.path);
				const text = doc ? summary(classes.get(doc)) : "";
				const name = doc ? `<a class="u" href="${classHref(doc)}">${esc(autoload.name)}</a>` : `<span class="u">${esc(autoload.name)}</span>`;
				return `<div class="row"><div class="sig">${doc ? dot(doc) + " " : ""}${name}  <span class="c">${esc(autoload.path)}</span></div>${text ? `<div class="doc">${esc(text)}</div>` : ""}</div>`;
			}).join("");
			html += "</div>";
		}
		if (readme) {
			html += `<div class="guide" style="margin-top:36px">${renderMarkdown(readme)}</div>`;
		}
		return { title: project.name, html };
	}

	function renderClass(name, anchor) {
		const model = classes.get(name);
		if (!model) {
			return { title: "Not found", html: `<p class="empty-state">No class named <code>${esc(name)}</code> in this build. It may be excluded, or the docs are older than the code.</p>` };
		}
		const reveal = showPrivate || (anchor || "").includes("-_");
		const visible = (item) => reveal || !item.name.startsWith("_");
		const autoload = model.inner ? null : autoloadByScript.get(model.path);
		const outer = outerName(name);

		let decl = dot(name);
		if (model.inner) {
			decl += `${keyword("class")} <span class="u">${esc(name.slice(outer.length + 1))}</span>`;
		} else if (name.startsWith('"')) {
			decl += `<span class="u">${esc(displayName(name))}</span>`;
		} else {
			decl += `${keyword("class_name")} <span class="u">${esc(name)}</span>`;
		}
		if (autoload) {
			decl += '<span class="badge">autoload</span>';
		}
		if (model.deprecated != null) {
			decl += '<span class="badge warn">deprecated</span>';
		}
		if (model.experimental != null) {
			decl += '<span class="badge warn">experimental</span>';
		}
		let sub = `${keyword("extends")} ${model.inherits ? typeHtml(model.inherits) : ""}  <span class="c">${esc(model.path)}</span>`;
		if (model.inner) {
			sub += `  inner class of ${classLink(outer)}`;
		}

		const facts = [];
		const chain = ancestors(name);
		if (chain.length) {
			facts.push(["Inherits", `<span class="mono">${chain.map(typeHtml).join(" &lt; ")}</span>`]);
		}
		const heirs = (children.get(name) || []).slice().sort((a, b) => byText(displayName(a), displayName(b)));
		if (heirs.length) {
			facts.push(["Inherited by", heirs.map((heir) => `<span class="mono">${classLink(heir)}</span>`).join(", ")]);
		}
		const users = model.inner ? [] : (usersByScript.get(model.path) || []).slice().sort((a, b) => Number(!SCENE_EXTENSIONS.test(a)) - Number(!SCENE_EXTENSIONS.test(b)) || byText(a, b));
		if (users.length) {
			const listed = users.map((user) => `<div class="mono">${esc(user)}</div>`).join("");
			facts.push(["Used by", users.length > 8 ? `<details><summary>${users.length} scenes and resources</summary>${listed}</details>` : listed]);
		}
		if (autoload) {
			facts.push(["Autoload", `<span class="mono">${esc(autoload.name)}</span>${autoload.global ? "" : " (not a global variable)"}`]);
		}
		const inners = Array.from(classes.keys()).filter((other) => other !== name && outerName(other) === name);
		if (inners.length) {
			facts.push(["Inner classes", inners.map((inner) => `<span class="mono">${classLink(inner)}</span>`).join(", ")]);
		}
		if (model.tutorials.length) {
			facts.push(["Tutorials", model.tutorials.map((link) => `<div><a class="external" href="${esc(link.url)}">${esc(link.title)}</a></div>`).join("")]);
		}

		let html = `<div class="hero"><div class="decl">${decl}</div><div class="sub">${sub}</div></div>`;
		html += notes(model);
		html += `<dl class="facts">${facts.map(([term, value]) => `<dt>${term}</dt><dd>${value}</dd>`).join("")}</dl>`;
		const description = model.brief || model.description
			? bbcode([model.brief, model.description].filter(Boolean).join("\n"), name)
			: model.comments[""] ? commentHtml(model.comments[""]) : "";
		html += description ? `<div class="description">${description}</div>` : `<p class="empty-state">No description yet. Add a ## or # comment under <code>extends</code>.</p>`;
		html += `<div class="toolbar"><label class="toggle"><input type="checkbox" id="show-private"${reveal ? " checked" : ""}> Show private members (_)</label></div>`;

		const row = (kind, item, sig) => {
			const doc = describe(item.description, model.comments[kind + "/" + item.name], name);
			return `<div class="row" id="${esc(kind + "-" + item.name)}"><div class="sig">${sig}</div>${doc ? `<div class="doc">${doc}</div>` : ""}${notes(item)}</div>`;
		};
		const section = (title, items, render) => {
			if (!items.length) {
				return "";
			}
			const shown = items.filter(visible);
			const hidden = items.length - shown.length;
			const count = `${shown.length}${hidden ? ` · ${hidden} private hidden` : ""}`;
			const rows = shown.length ? shown.map(render).join("") : `<div class="row"><div class="doc">Only private ${title.toLowerCase()} here.</div></div>`;
			return `<div class="bar">${title} <span class="count">${count}</span></div><div class="rows">${rows}</div>`;
		};

		const enums = new Map();
		for (const constant of model.constants.filter((item) => item.enum)) {
			if (!enums.has(constant.enum)) {
				enums.set(constant.enum, []);
			}
			enums.get(constant.enum).push(constant);
		}
		const enumItems = Array.from(enums, ([enumName, values]) => ({ name: enumName, values, description: "" }));

		html += section("Properties", model.members, (item) => row("member", item, memberSig(item)));
		html += section("Methods", model.methods, (item) => row("method", item, methodSig(item)));
		html += section("Signals", model.signals, (item) => row("signal", item, signalSig(item)));
		html += section("Enums", enumItems, (item) => row("enum", item, enumSig(item.name, item.values)));
		html += section("Constants", model.constants.filter((item) => !item.enum), (item) => row("constant", item, constantSig(item)));

		return {
			title: displayName(name),
			html,
			current: classHref(name),
			after() {
				document.getElementById("show-private").addEventListener("change", (event) => {
					showPrivate = event.target.checked;
					writeSetting("gddocs.showPrivate", showPrivate ? "1" : "0");
					render();
				});
				const target = anchor && document.getElementById(anchor);
				if (target) {
					target.classList.add("flash");
					target.scrollIntoView({ block: "center" });
				}
			},
		};
	}

	function renderTree() {
		const edges = new Map();
		const roots = new Set();
		for (const model of classes.values()) {
			if (model.inner) {
				continue;
			}
			let current = model.name;
			for (let depth = 0; depth < 64; depth++) {
				const parent = parentOf(current);
				if (!parent) {
					roots.add(current);
					break;
				}
				if (!edges.has(parent)) {
					edges.set(parent, new Set());
				}
				if (edges.get(parent).has(current)) {
					break;
				}
				edges.get(parent).add(current);
				current = parent;
			}
		}
		const kidsOf = (name) => Array.from(edges.get(name) || []).sort((a, b) => byText(displayName(a), displayName(b)));
		const projectCount = (name) => kidsOf(name).reduce((sum, kid) => sum + (classes.has(kid) ? 1 : 0) + projectCount(kid), 0);
		const label = (name) => (classes.has(name) ? classLink(name) : `<a href="${engineUrl(name)}" class="external">${esc(name)}</a>`);

		const node = (name) => {
			const chain = [name];
			let tail = name;
			while (!classes.has(tail) && kidsOf(tail).length === 1 && !classes.has(kidsOf(tail)[0])) {
				tail = kidsOf(tail)[0];
				chain.push(tail);
			}
			const kids = kidsOf(tail);
			const engine = !classes.has(tail);
			const count = projectCount(tail);
			const badge = kids.length ? ` <span class="kids">${count}</span>` : "";
			const tag = `<span class="node${engine ? " engine" : ""}">${dot(tail)}${chain.map(label).join(" › ")}${badge}</span>`;
			if (!kids.length) {
				return `<li>${tag}</li>`;
			}
			return `<li><details open><summary>${tag}</summary><ul>${kids.map(node).join("")}</ul></details></li>`;
		};

		const html = `<h1 class="page">Class tree</h1>
			<p class="lede">Every script class under the engine class it extends. Outlined dots are engine classes and link to the Godot reference; counts are project classes below a node.</p>
			<div class="toolbar"><input class="filter" id="tree-filter" type="search" placeholder="Filter the tree" aria-label="Filter the tree"></div>
			<div class="tree"><ul>${Array.from(roots).sort(byText).map(node).join("")}</ul></div>`;
		return { title: "Class tree", html, current: "#/tree", after: () => bindTreeFilter() };
	}

	function bindTreeFilter() {
		const input = document.getElementById("tree-filter");
		const walk = (li, query) => {
			const own = li.querySelector(":scope > details > summary > .node, :scope > .node");
			let below = false;
			for (const kid of li.querySelectorAll(":scope > details > ul > li")) {
				below = walk(kid, query) || below;
			}
			const hit = Boolean(query) && own.textContent.toLowerCase().includes(query);
			own.classList.toggle("match", hit);
			li.classList.toggle("hidden", Boolean(query) && !hit && !below);
			const details = li.querySelector(":scope > details");
			if (details) {
				details.open = !query || below;
			}
			return hit || below;
		};
		input.addEventListener("input", () => {
			const query = input.value.trim().toLowerCase();
			for (const li of document.querySelectorAll(".tree > ul > li")) {
				walk(li, query);
			}
		});
	}

	function renderScenes() {
		const files = Object.keys(DATA.usage).sort(byText);
		const table = (paths, empty) => {
			if (!paths.length) {
				return `<p class="empty-state">${empty}</p>`;
			}
			const rows = paths.map((path) => {
				const scripts = DATA.usage[path].map((script) => {
					const doc = topByPath.get(script);
					return doc ? `${dot(doc)} ${classLink(doc)}` : `<span class="c">${esc(script)}</span>`;
				}).join("<br>");
				const main = path === DATA.project.main_scene ? '<span class="badge">main</span>' : "";
				return `<tr data-filter="${esc((path + " " + DATA.usage[path].join(" ")).toLowerCase())}" id="${esc(path)}"><td class="mono">${esc(path)}${main}</td><td class="mono">${scripts}</td></tr>`;
			}).join("");
			return `<div class="table-wrap"><table class="grid"><thead><tr><th>File</th><th>Scripts</th></tr></thead><tbody>${rows}</tbody></table></div>`;
		};
		const html = `<h1 class="page">Scenes and resources</h1>
			<p class="lede">Files that reference a script, and which scripts they use.</p>
			<div class="toolbar"><input class="filter" id="table-filter" type="search" placeholder="Filter by file or script" aria-label="Filter scenes and resources"></div>
			<div class="bar">Scenes <span class="count">${files.filter((f) => SCENE_EXTENSIONS.test(f)).length}</span></div>
			${table(files.filter((f) => SCENE_EXTENSIONS.test(f)), "No scenes reference a script.")}
			<div class="bar">Resources <span class="count">${files.filter((f) => !SCENE_EXTENSIONS.test(f)).length}</span></div>
			${table(files.filter((f) => !SCENE_EXTENSIONS.test(f)), "No resources reference a script.")}`;
		return { title: "Scenes", html, current: "#/scenes", after: () => bindTableFilter() };
	}

	function renderSignals() {
		const rows = [];
		for (const model of Array.from(classes.values()).sort((a, b) => byText(displayName(a.name), displayName(b.name)))) {
			for (const signal of model.signals) {
				const doc = describe(signal.description, model.comments["signal/" + signal.name], model.name);
				const href = classHref(model.name, "signal-" + signal.name);
				rows.push(`<div class="row" data-filter="${esc((signal.name + " " + displayName(model.name)).toLowerCase())}">
					<div class="sig">${dot(model.name)} ${classLink(model.name)}.<a class="f" href="${href}">${esc(signal.name)}</a>(${paramsHtml(signal.params)})</div>
					${doc ? `<div class="doc">${doc}</div>` : ""}</div>`);
			}
		}
		const html = `<h1 class="page">Signals</h1>
			<p class="lede">Every signal the project declares, by class.</p>
			<div class="toolbar"><input class="filter" id="table-filter" type="search" placeholder="Filter by signal or class" aria-label="Filter signals"></div>
			${rows.length ? `<div class="bar">Signals <span class="count">${rows.length}</span></div><div class="rows">${rows.join("")}</div>` : '<p class="empty-state">No signals declared.</p>'}`;
		return { title: "Signals", html, current: "#/signals", after: () => bindTableFilter() };
	}

	function renderInput() {
		const html = `<h1 class="page">Input map</h1>
			<p class="lede">Actions from Project Settings and the events bound to them.</p>
			<div class="toolbar">
				<input class="filter" id="table-filter" type="search" placeholder="Filter by action or key" aria-label="Filter input actions">
				<label class="toggle"><input type="checkbox" id="show-builtin"> Show built-in ui_ actions</label>
			</div>
			<div class="table-wrap"><table class="grid"><thead><tr><th>Action</th><th>Events</th><th>Deadzone</th></tr></thead><tbody>
			${DATA.input.map((action) => `<tr data-filter="${esc((action.name + " " + action.events.join(" ")).toLowerCase())}"${action.builtin ? ' data-builtin="1"' : ""}>
				<td class="mono">${esc(action.name)}</td>
				<td>${action.events.length ? action.events.map((event) => `<kbd>${esc(event)}</kbd>`).join(" ") : '<span class="c">none</span>'}</td>
				<td class="mono">${action.deadzone}</td></tr>`).join("")}
			</tbody></table></div>`;
		return {
			title: "Input map",
			html,
			current: "#/input",
			after: () => bindTableFilter((row) => document.getElementById("show-builtin").checked || !row.dataset.builtin, "show-builtin"),
		};
	}

	function renderAutoloads() {
		const rows = DATA.autoloads.map((autoload) => {
			const doc = docForPath(autoload.path);
			const scripts = autoload.path.endsWith(".gd") ? [] : DATA.usage[autoload.path] || [];
			const typeCell = doc ? `${dot(doc)} ${classLink(doc)}` : scripts.map((script) => esc(script)).join("<br>");
			return `<tr data-filter="${esc((autoload.name + " " + autoload.path).toLowerCase())}">
				<td class="mono">${esc(autoload.name)}</td>
				<td class="mono">${typeCell}</td>
				<td class="summary">${doc ? esc(summary(classes.get(doc))) : ""}</td>
				<td class="mono path">${esc(autoload.path)}</td>
				<td>${autoload.global ? "Yes" : "No"}</td></tr>`;
		}).join("");
		const html = `<h1 class="page">Autoloads</h1>
			<p class="lede">Singletons loaded before any scene, in load order.</p>
			<div class="toolbar"><input class="filter" id="table-filter" type="search" placeholder="Filter autoloads" aria-label="Filter autoloads"></div>
			${DATA.autoloads.length ? `<div class="table-wrap"><table class="grid"><thead><tr><th>Name</th><th>Script</th><th>Summary</th><th>Path</th><th>Global</th></tr></thead><tbody>${rows}</tbody></table></div>` : '<p class="empty-state">This project has no autoloads.</p>'}`;
		return { title: "Autoloads", html, current: "#/autoloads", after: () => bindTableFilter() };
	}

	function renderGuide(path) {
		const guide = guideByPath.get(path);
		if (!guide) {
			return { title: "Not found", html: `<p class="empty-state">No guide at <code>${esc(path)}</code>. Check <code>gddocs/guides</code> in Project Settings.</p>` };
		}
		return { title: guide.title, html: `<div class="hero"><div class="sub">${esc(path)}</div></div><div class="guide">${renderMarkdown(guide)}</div>`, current: "#/guide/" + encodeURIComponent(path) };
	}

	function renderMarkdown(guide) {
		if (!window.marked) {
			return `<pre>${esc(guide.markdown)}</pre>`;
		}
		const dir = guide.path.slice(0, guide.path.lastIndexOf("/") + 1);
		const tokens = window.marked.lexer(guide.markdown);
		window.marked.walkTokens(tokens, (token) => {
			if ((token.type === "link" || token.type === "image") && token.href) {
				token.href = rebase(token.href, dir, token.type === "link");
			}
		});
		return window.marked.parser(tokens);
	}

	// Relative links in a guide point at files beside it; the page lives in the output folder.
	function rebase(href, dir, isLink) {
		if (/^[a-z][\w+.-]*:/i.test(href) || href.startsWith("#") || href.startsWith("/")) {
			return href;
		}
		const [file, fragment] = href.split("#");
		const resolved = normalize(dir + decodeURI(file));
		if (isLink && guideByPath.has(resolved)) {
			return "#/guide/" + encodeURIComponent(resolved);
		}
		return encodeURI(relative(outputDir, resolved)) + (fragment ? "#" + fragment : "");
	}

	function normalize(path) {
		const parts = [];
		for (const part of path.replace(/^res:\/\//, "").split("/")) {
			if (part === "..") {
				parts.pop();
			} else if (part && part !== ".") {
				parts.push(part);
			}
		}
		return "res://" + parts.join("/");
	}

	function relative(fromDir, to) {
		const from = fromDir.replace(/^res:\/\//, "").split("/").filter(Boolean);
		const target = to.replace(/^res:\/\//, "").split("/");
		let shared = 0;
		while (shared < from.length && shared < target.length - 1 && from[shared] === target[shared]) {
			shared++;
		}
		return "../".repeat(from.length - shared) + target.slice(shared).join("/");
	}

	function docForPath(path) {
		if (topByPath.has(path)) {
			return topByPath.get(path);
		}
		const scripts = DATA.usage[path] || [];
		return scripts.length === 1 ? topByPath.get(scripts[0]) : undefined;
	}

	function sceneLink(path) {
		return `<a class="mono" href="#/scenes">${esc(path)}</a>`;
	}

	function bindTableFilter(extra, toggleId) {
		const input = document.getElementById("table-filter");
		const apply = () => {
			const query = input.value.trim().toLowerCase();
			for (const row of document.querySelectorAll("[data-filter]")) {
				row.hidden = (query && !row.dataset.filter.includes(query)) || (extra && !extra(row));
			}
		};
		input.addEventListener("input", apply);
		if (toggleId) {
			document.getElementById(toggleId).addEventListener("change", apply);
		}
		apply();
	}

	// Sidebar and search

	const searchIndex = [];
	for (const model of classes.values()) {
		searchIndex.push({ label: displayName(model.name), sub: model.path, href: classHref(model.name), kind: "class", rank: 0, dot: model.name });
		const add = (kind, items) => {
			for (const item of items) {
				searchIndex.push({ label: item.name, sub: displayName(model.name), href: classHref(model.name, kind + "-" + item.name), kind: kind === "member" ? "property" : kind, rank: 1 });
			}
		};
		add("method", model.methods);
		add("member", model.members);
		add("signal", model.signals);
		add("constant", model.constants.filter((item) => !item.enum));
		add("enum", Array.from(new Set(model.constants.filter((item) => item.enum).map((item) => item.enum)), (enumName) => ({ name: enumName })));
	}
	for (const guide of guides) {
		searchIndex.push({ label: guide.title, sub: guide.path, href: "#/guide/" + encodeURIComponent(guide.path), kind: "guide", rank: 0 });
	}
	for (const autoload of DATA.autoloads) {
		searchIndex.push({ label: autoload.name, sub: autoload.path, href: "#/autoloads", kind: "autoload", rank: 0 });
	}
	for (const action of DATA.input.filter((item) => !item.builtin)) {
		searchIndex.push({ label: action.name, sub: action.events.join(", "), href: "#/input", kind: "input", rank: 1 });
	}

	function results(query) {
		const q = query.toLowerCase();
		const scored = [];
		for (const entry of searchIndex) {
			if (entry.label.startsWith("_") && !q.startsWith("_")) {
				continue;
			}
			const label = entry.label.toLowerCase();
			const at = label.indexOf(q);
			let score;
			if (label === q) {
				score = 0;
			} else if (at === 0) {
				score = 1;
			} else if (at > 0 && /[._\s]/.test(label[at - 1])) {
				score = 2;
			} else if (at > 0) {
				score = 3;
			} else if (entry.kind === "class" && entry.sub.toLowerCase().includes(q)) {
				score = 4;
			} else {
				continue;
			}
			scored.push([score * 2 + entry.rank, entry]);
		}
		return scored.sort((a, b) => a[0] - b[0] || byText(a[1].label, b[1].label)).slice(0, 80).map((pair) => pair[1]);
	}

	function renderSidebar() {
		const query = search.value.trim();
		if (query) {
			const hits = results(query);
			sidebar.innerHTML = `<div class="heading">${hits.length === 80 ? "Top 80 matches" : hits.length + " matches"}</div>` + (hits.length
				? hits.map((hit) => `<a href="${hit.href}" title="${esc(hit.sub)}">${hit.dot ? dot(hit.dot) : ""}<span class="mono">${esc(hit.label)}</span>${hit.kind === "class" ? "" : ` <span class="c">${esc(hit.sub)}</span>`}<span class="hit-kind">${hit.kind}</span></a>`).join("")
				: `<div class="empty">Nothing matches "${esc(query)}".</div>`);
			return;
		}

		const signalCount = Array.from(classes.values()).reduce((sum, model) => sum + model.signals.length, 0);
		const sceneCount = Object.keys(DATA.usage).length;
		const customInput = DATA.input.filter((action) => !action.builtin).length;
		let html = '<a href="#/">Overview</a>';
		if (guides.length) {
			const guideLink = (guide) => `<a href="#/guide/${encodeURIComponent(guide.path)}" title="${esc(guide.path)}">${esc(guide.title)}</a>`;
			html += '<div class="heading">Guides</div>';
			if (guides.length <= 8) {
				html += guides.map(guideLink).join("");
			} else {
				const folders = new Map();
				for (const guide of guides) {
					const folder = guide.path.replace(/^res:\/\//, "").split("/").slice(0, -1).join("/") || "res://";
					if (!folders.has(folder)) {
						folders.set(folder, []);
					}
					folders.get(folder).push(guide);
				}
				for (const [folder, list] of folders) {
					html += `<details><summary>${esc(folder)}<span class="count">${list.length}</span></summary><div>${list.map(guideLink).join("")}</div></details>`;
				}
			}
		}
		html += '<div class="heading">Project</div>';
		html += `<a href="#/tree">Class tree<span class="count">${topByPath.size}</span></a>`;
		html += `<a href="#/autoloads">Autoloads<span class="count">${DATA.autoloads.length}</span></a>`;
		html += `<a href="#/scenes">Scenes and resources<span class="count">${sceneCount}</span></a>`;
		html += `<a href="#/signals">Signals<span class="count">${signalCount}</span></a>`;
		html += `<a href="#/input">Input map<span class="count">${customInput}</span></a>`;

		html += '<div class="heading">Classes</div>';
		const groups = new Map();
		for (const model of classes.values()) {
			if (model.inner) {
				continue;
			}
			const folder = model.path.replace(/^res:\/\//, "").split("/").slice(0, -1).join("/") || "res://";
			if (!groups.has(folder)) {
				groups.set(folder, []);
			}
			groups.get(folder).push(model.name);
		}
		const openAll = classes.size <= 40;
		for (const folder of Array.from(groups.keys()).sort(byText)) {
			const names = groups.get(folder).sort((a, b) => byText(displayName(a), displayName(b)));
			const links = names.map((name) => {
				const inner = Array.from(classes.keys()).filter((other) => other !== name && outerName(other) === name);
				return `<a href="${classHref(name)}">${dot(name)}<span class="mono">${esc(displayName(name))}</span></a>`
					+ inner.map((innerName) => `<a class="inner" href="${classHref(innerName)}">${dot(innerName)}<span class="mono">${esc(displayName(innerName).slice(displayName(name).length))}</span></a>`).join("");
			}).join("");
			html += `<details${openAll ? " open" : ""}><summary>${esc(folder)}<span class="count">${names.length}</span></summary><div>${links}</div></details>`;
		}
		sidebar.innerHTML = html;
	}

	function markCurrent(href) {
		for (const link of sidebar.querySelectorAll("a.current")) {
			link.classList.remove("current");
		}
		const link = href && Array.from(sidebar.querySelectorAll("a")).find((candidate) => candidate.getAttribute("href") === href);
		if (!link) {
			return;
		}
		link.classList.add("current");
		const details = link.closest("details");
		if (details) {
			details.open = true;
		}
		link.scrollIntoView({ block: "nearest" });
	}

	// Routing

	function render() {
		const [page, ...rest] = location.hash.replace(/^#\/?/, "").split("/");
		const args = rest.map((part) => decodeURIComponent(part));
		let view;
		switch (page) {
			case "class":
				view = renderClass(args[0], args[1]);
				break;
			case "guide":
				view = renderGuide(args[0]);
				break;
			case "tree":
				view = renderTree();
				break;
			case "scenes":
				view = renderScenes();
				break;
			case "signals":
				view = renderSignals();
				break;
			case "input":
				view = renderInput();
				break;
			case "autoloads":
				view = renderAutoloads();
				break;
			default:
				view = renderOverview();
				view.current = "#/";
		}
		content.innerHTML = view.html;
		document.title = view.title && view.title !== DATA.project.name ? `${view.title} · ${DATA.project.name}` : DATA.project.name || "GDDocs";
		if (!args[1]) {
			window.scrollTo(0, 0);
		}
		if (view.after) {
			view.after();
		}
		markCurrent(view.current || location.hash);
		sidebar.classList.remove("open");
		document.getElementById("menu-toggle").setAttribute("aria-expanded", "false");
	}

	function readSetting(key) {
		try {
			return window.localStorage.getItem(key);
		} catch (error) {
			return null;
		}
	}

	function writeSetting(key, value) {
		try {
			window.localStorage.setItem(key, value);
		} catch (error) {
			// Private windows and file:// pages can refuse storage; the toggle still works for this visit.
		}
	}

	document.getElementById("project-name").textContent = DATA.project.name || "GDDocs";
	document.getElementById("project-version").textContent = [DATA.project.version, "Godot " + DATA.project.godot.split(".").slice(0, 3).join(".")].filter(Boolean).join(" · ");
	document.getElementById("menu-toggle").addEventListener("click", (event) => {
		const open = sidebar.classList.toggle("open");
		event.currentTarget.setAttribute("aria-expanded", String(open));
	});
	search.addEventListener("input", () => {
		renderSidebar();
		markCurrent(location.hash.split("/").slice(0, 3).join("/"));
		if (search.value.trim()) {
			sidebar.classList.add("open");
		}
	});
	search.addEventListener("keydown", (event) => {
		if (event.key === "Enter") {
			const first = sidebar.querySelector("a");
			if (first && search.value.trim()) {
				location.hash = first.getAttribute("href");
			}
		} else if (event.key === "Escape") {
			search.value = "";
			renderSidebar();
			markCurrent(location.hash.split("/").slice(0, 3).join("/"));
		}
	});
	document.addEventListener("keydown", (event) => {
		const typing = /^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName);
		if (event.key === "/" && !typing) {
			event.preventDefault();
			search.focus();
		}
	});
	window.addEventListener("hashchange", render);

	renderSidebar();
	render();
})();
