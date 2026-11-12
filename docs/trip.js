const REFRESH_MS = 15000;

const tripId = new URLSearchParams(window.location.search).get("id");
const carKey = `curva-car-${tripId}`;

// Brand icons are simple stand-ins. Swap in official assets if you want the real logos.
const ICONS = {
  waze: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#33ccff" d="M12 3a9 9 0 0 0-9 9c0 1.6.4 3 1.2 4.3L3 21l4.8-1.2A9 9 0 1 0 12 3z"/><circle cx="9" cy="11" r="1.3" fill="#fff"/><circle cx="15" cy="11" r="1.3" fill="#fff"/></svg>',
  google: '<svg viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285f4" d="M12 2a7 7 0 0 0-7 7c0 5.2 7 13 7 13s7-7.8 7-13a7 7 0 0 0-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z"/></svg>',
};

const statusBox = document.getElementById("status");
const tripSection = document.getElementById("trip");
const titleEl = document.getElementById("trip-title");
const masterLink = document.getElementById("master-link");
const tripDone = document.getElementById("trip-done");
const joinSection = document.getElementById("join");
const carChoices = document.getElementById("car-choices");
const carNameInput = document.getElementById("car-name");
const joinButton = document.getElementById("join-car");
const mineSection = document.getElementById("mine");
const myName = document.getElementById("my-name");
const myBar = document.getElementById("my-bar");
const myProgress = document.getElementById("my-progress");
const nextCard = document.getElementById("next-card");
const nextName = document.getElementById("next-name");
const nextNav = document.getElementById("next-nav");
const markButton = document.getElementById("mark-reached");
const myFinished = document.getElementById("my-finished");
const undoButton = document.getElementById("undo");
const switchButton = document.getElementById("switch-car");
const carsList = document.getElementById("cars-list");
const stopList = document.getElementById("stop-list");
const completeButton = document.getElementById("complete-trip");
const messageBox = document.getElementById("message");
const signinSection = document.getElementById("signin");
const accountBar = document.getElementById("account");
const invitationSection = document.getElementById("invitation");
const profileSection = document.getElementById("profile");

let state = null; // { trip, cars } from the server
let myCarId = localStorage.getItem(carKey);
let busy = false;
let myProfile = null;
let carNameTouched = false;

function stopName(stop) {
  return typeof stop === "string" ? stop : stop.name;
}

// Only https links are used, so a link saved in a trip can't run script.
function safeUrl(url) {
  return typeof url === "string" && url.startsWith("https://") ? url : null;
}

function wazeUrl(stop) {
  const custom = typeof stop === "object" ? safeUrl(stop.waze) : null;
  return custom ?? `https://www.waze.com/ul?q=${encodeURIComponent(stopName(stop))}&navigate=yes`;
}

function googleUrl(stop) {
  const custom = typeof stop === "object" ? safeUrl(stop.google) : null;
  return custom ?? `https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(stopName(stop))}`;
}

function navButtons(stop) {
  const wrapper = document.createElement("div");
  wrapper.className = "nav-row";
  const name = stopName(stop);

  const waze = document.createElement("a");
  waze.className = "icon-btn";
  waze.href = wazeUrl(stop);
  waze.target = "_blank";
  waze.rel = "noopener";
  waze.setAttribute("aria-label", `Open ${name} in Waze`);
  waze.innerHTML = `${ICONS.waze}<span>Waze</span>`;

  const google = document.createElement("a");
  google.className = "icon-btn";
  google.href = googleUrl(stop);
  google.target = "_blank";
  google.rel = "noopener";
  google.setAttribute("aria-label", `Open ${name} in Google Maps`);
  google.innerHTML = `${ICONS.google}<span>Google</span>`;

  wrapper.append(waze, google);
  return wrapper;
}

function showMessage(text) {
  messageBox.textContent = text;
  messageBox.hidden = false;
}

function hideMessage() {
  messageBox.hidden = true;
  messageBox.textContent = "";
}

// api.js throws this when a saved session was refused. The fix is to sign in again.
function sessionEnded(error) {
  if (!error.message.includes("[CURVA_SESSION_EXPIRED]")) return false;
  needSignIn("Your sign-in has ended. Sign in again to keep going.");
  return true;
}

function formatTime(iso) {
  return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

function carProgressText(car, total) {
  return `${car.reached} of ${total} reached`;
}

function renderChoices(cars) {
  carChoices.replaceChildren();
  if (cars.length === 0) {
    const empty = document.createElement("li");
    empty.className = "muted";
    empty.textContent = "No cars have joined yet. Add yours below.";
    carChoices.append(empty);
    return;
  }
  cars.forEach((car) => {
    const item = document.createElement("li");
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = car.name;
    button.addEventListener("click", () => chooseCar(car.id));
    item.append(button);
    carChoices.append(item);
  });
}

function renderMine(car, total) {
  const stops = state.trip.stops;
  const done = Boolean(state.trip.completed_at);
  const atEnd = car.reached >= total;

  myName.textContent = car.name;
  myBar.style.width = `${(car.reached / total) * 100}%`;
  myProgress.textContent = carProgressText(car, total);

  nextCard.hidden = done || atEnd;
  myFinished.hidden = done || !atEnd;
  if (!atEnd) {
    const next = stops[car.reached];
    nextName.textContent = stopName(next);
    nextNav.replaceChildren(...navButtons(next).children);
  }

  markButton.textContent = busy ? "Saving…" : "Mark as reached";
  markButton.disabled = busy || done;
  undoButton.disabled = busy || done || car.reached === 0;
}

function renderGroup(cars, total, myId) {
  const stops = state.trip.stops;
  carsList.replaceChildren();
  cars.forEach((car) => {
    const item = document.createElement("li");
    item.className = "car";

    const header = document.createElement("div");
    header.className = "car-header";
    const name = document.createElement("span");
    name.className = "name";
    name.textContent = car.id === myId ? `${car.name} (you)` : car.name;
    const count = document.createElement("span");
    count.className = "muted";
    count.textContent = carProgressText(car, total);
    const who = document.createElement("span");
    who.className = "car-who";
    if (car.person) {
      // Name the person; the car name stays as the title. Legacy cars have no person.
      const person = document.createElement("span");
      person.className = "muted";
      person.textContent = car.person.name;
      const titles = document.createElement("span");
      titles.className = "car-titles";
      titles.append(name, person);
      who.append(avatarNode(car.person.avatar_colour, car.person.avatar_shape, car.person.name), titles);
    } else {
      who.append(name);
    }
    header.append(who, count);

    const bar = document.createElement("div");
    bar.className = "progress";
    const fill = document.createElement("span");
    fill.style.width = `${(car.reached / total) * 100}%`;
    bar.append(fill);

    const where = document.createElement("p");
    where.className = "muted";
    where.textContent = car.reached === 0
      ? "Not started yet"
      : `Last check-in ${formatTime(car.checked_in_at)}: ${stopName(stops[car.reached - 1])}`;

    item.append(header, bar, where);
    carsList.append(item);
  });
}

function renderStops(myCar) {
  const stops = state.trip.stops;
  stopList.replaceChildren();
  stops.forEach((stop, index) => {
    const item = document.createElement("li");
    if (myCar && index < myCar.reached) item.className = "done";
    else if (myCar && index === myCar.reached) item.className = "next";

    const tick = document.createElement("span");
    tick.className = "tick";
    tick.textContent = myCar && index < myCar.reached ? "✓" : "";

    const num = document.createElement("span");
    num.className = "num";
    num.textContent = `${index + 1}.`;

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = stopName(stop);

    item.append(tick, num, name, ...navButtons(stop).children);
    stopList.append(item);
  });
}

function render() {
  const { trip, cars } = state;
  const total = trip.stops.length;
  const done = Boolean(trip.completed_at);

  titleEl.textContent = trip.name;
  document.title = `Curva · ${trip.name}`;

  const master = safeUrl(trip.master_url);
  masterLink.hidden = !master;
  if (master) masterLink.href = master;

  tripDone.hidden = !done;
  if (done) tripDone.textContent = `Trip completed at ${formatTime(trip.completed_at)}. Check-ins are closed.`;
  completeButton.hidden = done;

  const me = cars.find((car) => car.id === myCarId);
  if (!me) {
    myCarId = null;
    localStorage.removeItem(carKey);
    joinSection.hidden = false;
    mineSection.hidden = true;
    renderChoices(cars);
    prefillCarName();
  } else {
    joinSection.hidden = true;
    mineSection.hidden = false;
    renderMine(me, total);
  }

  renderGroup(cars, total, myCarId);
  renderStops(me);

  tripSection.hidden = false;
  statusBox.hidden = true;
}

// Fills the join box from the profile (car, else name) until the person types their own.
// The server only keeps 40 characters of a car name, and the profile car can be 60.
async function prefillCarName() {
  if (carNameTouched || carNameInput.value || !signInRequired()) return;
  if (!myProfile) {
    if (!(await getSession())) return;
    try {
      myProfile = await fetchMyProfile();
    } catch {
      return;
    }
  }
  if (!myProfile || carNameTouched || carNameInput.value) return;
  carNameInput.value = (myProfile.car_text || myProfile.display_name || "").slice(0, MAX_NAME);
}

function formatDate(iso) {
  const [year, month, day] = iso.split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString([], { day: "numeric", month: "short", year: "numeric" });
}

function datesText(invitation) {
  const { starts_on: starts, ends_on: ends } = invitation;
  if (starts && ends && starts !== ends) return `${formatDate(starts)} to ${formatDate(ends)}`;
  if (starts || ends) return formatDate(starts || ends);
  return "";
}

// What a signed-out visitor sees on a private trip: who invited them, and nothing about the route.
function renderInvitation(invitation) {
  const cars = invitation.car_count === 1 ? "1 car" : `${invitation.car_count} cars`;
  const lines = [`Invited by ${invitation.invited_by}`, datesText(invitation), `${cars} so far`].filter(Boolean);

  const signUp = element("button", "primary", "Sign up to see the route and join");
  signUp.type = "button";
  signUp.addEventListener("click", () => {
    signUp.hidden = true;
    needSignIn("Enter your email and we'll send a code. Next you'll add your name.");
  });

  invitationSection.replaceChildren(
    element("p", "label", "You're invited"),
    element("h1", "", invitation.trip_name),
    ...lines.map((line) => element("p", "muted", line)),
    signUp
  );
  invitationSection.hidden = false;
  document.title = `Curva · ${invitation.trip_name}`;
}

async function showInvitation() {
  if (!invitationSection.hidden || !signinSection.hidden) return;
  const invitation = await callFunction("trip_invitation", { p_trip: tripId });
  if (invitation.status !== "ok") {
    statusBox.hidden = false;
    statusBox.textContent = "This trip doesn't exist. Check the link.";
    return;
  }
  statusBox.hidden = true;
  renderInvitation(invitation);
}

function closeProfileStep() {
  profileSection.hidden = true;
  profileSection.replaceChildren();
  tripSection.hidden = !state;
  statusBox.hidden = Boolean(state);
  if (!state) statusBox.textContent = "Loading trip…";
}

// Shows the profile step. With `editing` it can be cancelled. With `retryJoin` the join that
// was refused is run again once the profile is saved.
function needProfile(message, { editing = false, retryJoin = false } = {}) {
  if (!profileSection.hidden) return;
  statusBox.hidden = true;
  tripSection.hidden = true;
  invitationSection.hidden = true;
  signinSection.hidden = true;
  profileSection.hidden = false;
  mountProfileStep(profileSection, {
    message,
    profile: editing ? myProfile : null,
    onSaved: async (profile) => {
      myProfile = profile;
      closeProfileStep();
      await load();
      if (retryJoin && state && !myCarId) joinNewCar();
    },
    onCancel: editing ? closeProfileStep : null,
  });
}

async function editProfile() {
  if (!myProfile) {
    try {
      myProfile = await fetchMyProfile();
    } catch (error) {
      if (!sessionEnded(error)) showMessage(`Couldn't load your profile: ${error.message}`);
      return;
    }
  }
  needProfile("Update the name, car and avatar friends see on your trips.", { editing: true });
}

// Asks the person to sign in. Built once, so the 15 second refresh doesn't wipe a half-typed code.
function needSignIn(message) {
  renderAccountBar(accountBar, onAccountChange, editProfile);
  if (!signinSection.hidden) return;
  if (!state) statusBox.hidden = true;
  signinSection.hidden = false;
  mountSignIn(signinSection, {
    message,
    onSignedIn: () => {
      signinSection.hidden = true;
      signinSection.replaceChildren();
      invitationSection.hidden = true;
      hideMessage();
      renderAccountBar(accountBar, onAccountChange, editProfile);
      load();
    },
  });
}

// After sign-out the page asks again, so a trip that needs an account is not left open.
function onAccountChange() {
  state = null;
  myProfile = null;
  carNameTouched = false;
  carNameInput.value = "";
  invitationSection.hidden = true;
  profileSection.hidden = true;
  profileSection.replaceChildren();
  tripSection.hidden = true;
  statusBox.hidden = false;
  statusBox.textContent = "Loading trip…";
  load();
}

async function load() {
  if (!profileSection.hidden) return; // don't pull the profile form out from under someone typing
  try {
    const data = await callFunction("get_trip", { p_id: tripId });
    if (!data) {
      statusBox.textContent = "This trip doesn't exist. Check the link.";
      return;
    }
    if (data.status === "sign_in_required") {
      await showInvitation();
      return;
    }
    if (data.status === "profile_required") {
      needProfile("Add your name so the group knows who you are. You can add a car and avatar too.");
      return;
    }
    state = data;
    render();
  } catch (error) {
    if (sessionEnded(error)) return;
    if (!state) {
      statusBox.textContent = error.message;
    } else {
      showMessage(`Couldn't refresh: ${error.message}`);
    }
  }
}

// Every car action returns the latest trip and cars, plus a status.
function applyResult(result) {
  if (result.trip) state = { trip: result.trip, cars: result.cars };

  const messages = {
    conflict: "That car's position changed on another phone. Showing the latest.",
    finished: "That car has already reached the last stop.",
    completed: "The trip is completed, so check-ins are closed.",
    nothing_to_undo: "Nothing to undo yet.",
    not_found: "That car no longer exists. Pick your car again.",
    forbidden: "You can only change your own car, and only the planner can complete the trip.",
  };
  if (messages[result.status]) showMessage(messages[result.status]);
  if (result.status === "profile_required") needProfile("Add your name before you continue.");
  if (result.status === "sign_in_required") needSignIn("Your sign-in has ended. Sign in again to keep checking in.");
  if (result.status === "not_found") {
    myCarId = null;
    localStorage.removeItem(carKey);
  }
  if (state) render();
}

async function runCarAction(functionName, body) {
  if (busy || !state) return;
  busy = true;
  markButton.textContent = "Saving…";
  markButton.disabled = true;
  undoButton.disabled = true;
  hideMessage();
  try {
    applyResult(await callFunction(functionName, body));
  } catch (error) {
    if (!sessionEnded(error)) showMessage(`Couldn't save that: ${error.message}`);
  } finally {
    busy = false;
    if (state) render();
  }
}

function markCar() {
  const me = state.cars.find((car) => car.id === myCarId);
  if (!me) return;
  runCarAction("mark_car", { p_car: myCarId, p_expected: me.reached });
}

function undoCar() {
  const me = state.cars.find((car) => car.id === myCarId);
  if (!me) return;
  runCarAction("undo_car", { p_car: myCarId, p_expected: me.reached });
}

function chooseCar(id) {
  myCarId = id;
  localStorage.setItem(carKey, id);
  render();
}

async function joinNewCar() {
  const name = carNameInput.value.trim();
  if (!name) {
    showMessage("Enter a car name first.");
    carNameInput.focus();
    return;
  }
  if (busy) return;
  busy = true;
  joinButton.disabled = true;
  hideMessage();
  try {
    const result = await callFunction("join_car", { p_trip: tripId, p_name: name });
    if (result.status === "ok") {
      state = { trip: result.trip, cars: result.cars };
      chooseCar(result.car_id);
      carNameInput.value = "";
      carNameTouched = false;
    } else if (result.status === "profile_required") {
      needProfile("Add your name before you join. Your car name comes from your profile.", { retryJoin: true });
    } else if (result.status === "sign_in_required") {
      needSignIn("Sign in with your email to join this trip.");
    } else {
      showMessage("This trip no longer exists.");
    }
  } catch (error) {
    if (!sessionEnded(error)) showMessage(`Couldn't join: ${error.message}`);
  } finally {
    busy = false;
    joinButton.disabled = false;
    if (state) render();
  }
}

async function completeTrip() {
  if (busy || !state) return;
  if (!window.confirm("Complete the trip? Check-ins will be closed for everyone.")) return;
  busy = true;
  hideMessage();
  try {
    applyResult(await callFunction("complete_trip", { p_trip: tripId }));
  } catch (error) {
    if (!sessionEnded(error)) showMessage(`Couldn't complete the trip: ${error.message}`);
  } finally {
    busy = false;
    if (state) render();
  }
}

markButton.addEventListener("click", markCar);
undoButton.addEventListener("click", undoCar);
joinButton.addEventListener("click", joinNewCar);
carNameInput.addEventListener("input", () => {
  carNameTouched = true;
});
carNameInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter") {
    event.preventDefault();
    joinNewCar();
  }
});
switchButton.addEventListener("click", () => {
  myCarId = null;
  localStorage.removeItem(carKey);
  render();
});
completeButton.addEventListener("click", completeTrip);

if (!tripId) {
  statusBox.textContent = "This link has no trip in it. Ask the person who shared it for the full link.";
} else {
  renderAccountBar(accountBar, onAccountChange, editProfile);
  load();
  setInterval(() => {
    if (!busy && document.visibilityState === "visible") load();
  }, REFRESH_MS);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && !busy) load();
  });
}
