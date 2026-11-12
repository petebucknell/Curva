// Profiles: the name, optional car and optional preset avatar a person uses on every trip.
// The database stores only the avatar keys below, so presets can change without a migration.
const MAX_NAME = 40;
const MAX_CAR = 60;

// DEFAULT presets (6 colours, 4 car silhouettes). Edit here to change the set.
const AVATAR_COLOURS = {
  peach: "#f2b07a",
  sage: "#9dbf9e",
  sky: "#8fb8d6",
  sand: "#d9c9a3",
  rose: "#d99a9a",
  lilac: "#b8a6d9",
};
const AVATAR_SHAPES = {
  coupe: { label: "Coupe", body: "M5 30v-4l6-2 7-6h12l8 6 6 1v5z" },
  hatch: { label: "Hatchback", body: "M5 30v-5l5-1 4-7h14l6 7h8v6z" },
  suv: { label: "SUV", body: "M5 30v-8l4-1 3-5h22l4 5 5 1v8z" },
  wagon: { label: "Wagon", body: "M5 30v-5l6-2 6-6h20l3 6h3v7z" },
};
const SILHOUETTE_COLOUR = "#242624";
const DEFAULT_AVATAR_BACKGROUND = "#343735";

const SVG_NS = "http://www.w3.org/2000/svg";

function svgNode(tag, attributes) {
  const node = document.createElementNS(SVG_NS, tag);
  Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, value));
  return node;
}

function hasKey(table, key) {
  return typeof key === "string" && Object.prototype.hasOwnProperty.call(table, key);
}

// A round avatar. Falls back to the person's initial when no preset is chosen.
function avatarNode(colourKey, shapeKey, name) {
  const wrapper = document.createElement("span");
  wrapper.className = "avatar";
  wrapper.setAttribute("aria-hidden", "true");

  if (!hasKey(AVATAR_COLOURS, colourKey) && !hasKey(AVATAR_SHAPES, shapeKey)) {
    wrapper.classList.add("initial");
    wrapper.textContent = (String(name || "?").trim().charAt(0) || "?").toUpperCase();
    return wrapper;
  }

  const background = hasKey(AVATAR_COLOURS, colourKey) ? AVATAR_COLOURS[colourKey] : DEFAULT_AVATAR_BACKGROUND;
  const shape = hasKey(AVATAR_SHAPES, shapeKey) ? AVATAR_SHAPES[shapeKey] : AVATAR_SHAPES.coupe;
  const svg = svgNode("svg", { viewBox: "0 0 48 48" });
  svg.append(
    svgNode("circle", { cx: 24, cy: 24, r: 24, fill: background }),
    svgNode("path", { d: shape.body, fill: SILHOUETTE_COLOUR }),
    svgNode("circle", { cx: 14, cy: 30, r: 4, fill: SILHOUETTE_COLOUR, stroke: background, "stroke-width": 1.5 }),
    svgNode("circle", { cx: 35, cy: 30, r: 4, fill: SILHOUETTE_COLOUR, stroke: background, "stroke-width": 1.5 })
  );
  wrapper.append(svg);
  return wrapper;
}

// The caller's profile, or null if they have not made one.
function fetchMyProfile() {
  return callFunction("get_my_profile", {});
}

// Builds the profile form inside `container`. Calls onSaved(profile) after a save.
// Pass onCancel to show a Cancel button (for editing an existing profile).
function mountProfileStep(container, { message, profile, onSaved, onCancel }) {
  container.replaceChildren();
  let colour = profile && hasKey(AVATAR_COLOURS, profile.avatar_colour) ? profile.avatar_colour : null;
  let shape = profile && hasKey(AVATAR_SHAPES, profile.avatar_shape) ? profile.avatar_shape : null;

  const intro = element("p", "muted", message);
  const errorBox = element("p", "error");
  errorBox.setAttribute("role", "alert");
  errorBox.hidden = true;

  const nameLabel = element("label", "", "Your name");
  nameLabel.htmlFor = "profile-name";
  const nameInput = element("input");
  nameInput.type = "text";
  nameInput.id = "profile-name";
  nameInput.maxLength = MAX_NAME;
  nameInput.autocomplete = "name";
  nameInput.placeholder = "Anna";
  nameInput.value = profile ? profile.display_name : "";

  const carLabel = element("label", "", "Your car (optional)");
  carLabel.htmlFor = "profile-car";
  const carInput = element("input");
  carInput.type = "text";
  carInput.id = "profile-car";
  carInput.maxLength = MAX_CAR;
  carInput.autocomplete = "off";
  carInput.placeholder = "Porsche 911 GT3";
  carInput.value = profile && profile.car_text ? profile.car_text : "";

  const avatarTitle = element("p", "label", "Avatar (optional)");
  const preview = element("div", "avatar-preview");
  const colourGroup = element("div", "choice-row");
  colourGroup.setAttribute("role", "group");
  colourGroup.setAttribute("aria-label", "Avatar colour");
  const shapeGroup = element("div", "choice-row");
  shapeGroup.setAttribute("role", "group");
  shapeGroup.setAttribute("aria-label", "Car silhouette");

  function refreshPreview() {
    preview.replaceChildren(avatarNode(colour, shape, nameInput.value));
    colourGroup.querySelectorAll("button").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.key === colour));
    });
    shapeGroup.querySelectorAll("button").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.key === shape));
    });
  }

  Object.entries(AVATAR_COLOURS).forEach(([key, hex]) => {
    const button = element("button", "swatch");
    button.type = "button";
    button.dataset.key = key;
    button.style.background = hex;
    button.setAttribute("aria-label", `Colour ${key}`);
    button.addEventListener("click", () => {
      colour = colour === key ? null : key;
      refreshPreview();
    });
    colourGroup.append(button);
  });
  Object.entries(AVATAR_SHAPES).forEach(([key, preset]) => {
    const button = element("button", "shape-choice");
    button.type = "button";
    button.dataset.key = key;
    button.setAttribute("aria-label", preset.label);
    const svg = svgNode("svg", { viewBox: "0 10 48 28" });
    svg.setAttribute("aria-hidden", "true");
    svg.append(
      svgNode("path", { d: preset.body, fill: "currentColor" }),
      svgNode("circle", { cx: 14, cy: 30, r: 4, fill: "currentColor" }),
      svgNode("circle", { cx: 35, cy: 30, r: 4, fill: "currentColor" })
    );
    button.append(svg);
    button.addEventListener("click", () => {
      shape = shape === key ? null : key;
      refreshPreview();
    });
    shapeGroup.append(button);
  });

  const saveButton = element("button", "primary", "Save and continue");
  saveButton.type = "submit";
  const buttons = [saveButton];
  if (onCancel) {
    const cancelButton = element("button", "quiet", "Cancel");
    cancelButton.type = "button";
    cancelButton.addEventListener("click", onCancel);
    buttons.push(cancelButton);
  }

  const form = element("form", "profile-form");
  form.noValidate = true;
  form.append(nameLabel, nameInput, carLabel, carInput, avatarTitle, preview, colourGroup, shapeGroup, errorBox, ...buttons);
  container.append(intro, form);
  refreshPreview();

  function showError(text) {
    errorBox.textContent = text;
    errorBox.hidden = false;
  }

  nameInput.addEventListener("input", refreshPreview);
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const name = nameInput.value.trim();
    if (!name) {
      showError("Enter your name.");
      nameInput.focus();
      return;
    }
    errorBox.hidden = true;
    saveButton.disabled = true;
    try {
      const result = await callFunction("save_profile", {
        p_name: name,
        p_car: carInput.value.trim(),
        p_avatar_colour: colour || "",
        p_avatar_shape: shape || "",
      });
      if (result.status === "ok") {
        onSaved(result.profile);
        return;
      }
      showError("Your sign-in has ended. Sign in again, then save your profile.");
    } catch (error) {
      showError(error.message);
    } finally {
      saveButton.disabled = false;
    }
  });
}
