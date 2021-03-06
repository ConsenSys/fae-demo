/* eslint-disable */
import { Map } from "immutable";

import reducer from "../auth";
import * as types from "../../actions/types";

const initialState = Map({
  authenticated: false,
  username: null,
  error: null,
  isLoading: false
});

describe("auth reducer", () => {
  it("should return the initial state", () => {
    expect(reducer(undefined, {})).toEqual(initialState);
  });

  it("should handle authentication success", () => {
    const username = 'Argo'
    const expectedState = Map({
      authenticated: true,
      username,
      error: null,
      isLoading: false
    });

    expect(
      reducer(initialState,
        { type: types.AUTHENTICATED, username }
      ))
      .toEqual(expectedState)
  });


  it("should handle authentication errors", () => {
    const error = '404'
    const expectedState = Map({
      authenticated: false,
      username: null,
      error,
      isLoading: false
    });

    expect(reducer(
      initialState, { type: types.AUTHENTICATION_ERROR, error }
    )).toEqual(expectedState)
  });

  it("should handle logout", () => {
    const initialState = Map({
      authenticated: true,
      username: 'Argo',
      error: null,
      isLoading: false
    });
    const expectedState = Map({
      authenticated: false,
      username: null,
      error: null,
      isLoading: false
    });

    expect(reducer(initialState, { type: types.UNAUTHENTICATED })).toEqual(expectedState)
  });
});