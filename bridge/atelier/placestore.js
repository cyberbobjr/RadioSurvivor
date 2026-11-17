// The shared places of the page (E25-T03, ADR lieux communs D02, D06): one model of personas/_places.txt read and
// written through GET / PUT /api/places, used by the Places tab and by every place list of the voice editor. A file
// the game would refuse (a place without a name or a square, a zone too big) is never written: save() says which
// place to finish. Listeners hear the changes of the list (loaded, a place made or removed), not each typed letter.

import * as places from './places.js';

export function createPlaceStore(api, catalog) {
  let model = places.newPlacesFile(catalog.sheet.format);
  let loaded = false;
  const listeners = new Set();
  const notify = () => listeners.forEach((fn) => fn());

  // Places that the game would refuse: [{place, problems}].
  const unfinished = () => places.list(model).map((place) => ({ place, problems: places.problems(place, catalog) }))
    .filter((p) => p.problems.length);

  const store = {
    get model() { return model; },
    get loaded() { return loaded; },
    list: () => places.list(model),
    find: (id) => places.find(model, id),
    choices: (options) => places.choices(model, options),
    unfinished,
    full: () => places.list(model).length >= catalog.sheet.maxPlaces,
    onChange: (fn) => { listeners.add(fn); return () => listeners.delete(fn); },

    async load() {
      const result = await api.places();
      if (!result.ok) return result;
      model = (result.text ?? '').trim() ? places.parsePlaces(result.text) : places.newPlacesFile(catalog.sheet.format);
      loaded = true;
      notify();
      return result;
    },

    // Writes the file; {ok: false, code: 'places_unfinished', place} while a place is not finished.
    async save() {
      const open = unfinished()[0];
      if (open) return { ok: false, code: 'places_unfinished', place: open.place, problems: open.problems };
      return api.savePlaces(places.serialize(model));
    },

    // A new place (values of places.addPlace), saved at once; its id, or null when the save was refused.
    async create(values) {
      const section = places.addPlace(model, values);
      const result = await store.save();
      if (!result.ok) {
        places.removePlace(model, section.id);
        notify();
        return { id: null, result };
      }
      notify();
      return { id: section.id, result };
    },

    change() { notify(); },
    remove(id) { places.removePlace(model, id); notify(); },
  };
  return store;
}
