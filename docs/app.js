const MAX_STOPS = 50;

const form = document.getElementById("trip-form");
const tripName = document.getElementById("trip-name");
const stopName = document.getElementById("stop-name");
const addButton = document.getElementById("add-stop");
const stopList = document.getElementById("stop-list");
const stopEmpty = document.getElementById("stop-empty");
const errorBox = document.getElementById("error");
const result = document.getElementById("result");
const tripLink = document.getElementById("trip-link");
const copyButton = document.getElementById("copy-link");
const createButton = form.querySelector("button[type='submit']");
const masterInput = document.getElementById("master-url");

let stops = [];

function render() {
  stopList.replaceChildren();
  stops.forEach((stop, index) => {
    const item = document.createElement("li");

    const num = document.createElement("span");
    num.className = "num";
    num.textContent = `${index + 1}.`;

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = stop;

    const up = moveButton("↑", "Move up", index === 0, () => move(index, -1));
    const down = moveButton("↓", "Move down", index === stops.length - 1, () => move(index, 1));

    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "remove";
    remove.textContent = "Remove";
    remove.setAttribute("aria-label", `Remove stop ${index + 1}: ${stop}`);
    remove.addEventListener("click", () => {
      stops.splice(index, 1);
      render();
    });

    item.append(num, name, up, down, remove);
    stopList.append(item);
  });

  stopEmpty.hidden = stops.length > 0;
  addButton.disabled = stops.length >= MAX_STOPS;
}

function moveButton(label, ariaLabel, disabled, onClick) {
  const button = document.createElement("button");
  button.type = "button";
  button.textContent = label;
  button.setAttribute("aria-label", ariaLabel);
  button.disabled = disabled;
  button.addEventListener("click", onClick);
  return button;
}

function move(index, direction) {
  const target = index + direction;
  if (target < 0 || target >= stops.length) return;
  [stops[index], stops[target]] = [stops[target], stops[index]];
  render();
}

function addStop() {
  const value = stopName.value.trim();
  if (!value) return;
  if (stops.length >= MAX_STOPS) {
    showError(`A trip can have up to ${MAX_STOPS} stops.`);
    return;
  }
  stops.push(value);
  stopName.value = "";
  hideError();
  render();
  stopName.focus();
}

function showError(message) {
  errorBox.textContent = message;
  errorBox.hidden = false;
}

function hideError() {
  errorBox.hidden = true;
  errorBox.textContent = "";
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const name = tripName.value.trim();

  if (!name) {
    showError("Give the trip a name.");
    tripName.focus();
    return;
  }
  if (stops.length === 0) {
    showError("Add at least one stop.");
    stopName.focus();
    return;
  }

  hideError();
  createButton.disabled = true;
  try {
    const masterUrl = masterInput.value.trim();
    const id = await callFunction("create_trip", {
      p_name: name,
      p_stops: stops,
      p_master_url: masterUrl || null,
    });
    const url = new URL("trip.html", window.location.href);
    url.searchParams.set("id", id);
    tripLink.value = url.href;
    result.hidden = false;
    tripLink.select();
  } catch (error) {
    if (error.message.includes("[CURVA_SESSION_EXPIRED]")) {
      showFormOrSignIn();
    } else {
      showError(error.message);
    }
  } finally {
    createButton.disabled = false;
  }
});

copyButton.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(tripLink.value);
    copyButton.textContent = "Copied";
  } catch {
    tripLink.select();
  }
});

const signinSection = document.getElementById("signin");
const accountBar = document.getElementById("account");

// With sign-in switched on, the form waits for a session. Off, the page works as before.
async function showFormOrSignIn() {
  renderAccountBar(accountBar, showFormOrSignIn);
  if (!signInRequired()) return;

  const session = await getSession();
  form.hidden = !session;
  if (session) {
    signinSection.hidden = true;
    signinSection.replaceChildren();
    return;
  }
  result.hidden = true;
  signinSection.hidden = false;
  mountSignIn(signinSection, {
    message: "Sign in with your email to create a trip. Friends will sign in the same way to join.",
    onSignedIn: showFormOrSignIn,
  });
}

addButton.addEventListener("click", addStop);

stopName.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    addStop();
  }
});

render();
showFormOrSignIn();
