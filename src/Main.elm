module Main exposing (..)

import Browser
import Browser.Dom as Dom
import Browser.Navigation as Nav
import Common exposing (..)
import Console
import Css.Global exposing (global)
import Data
import Deque
import Dict
import Face exposing (view)
import Game
import Html.Styled exposing (Html, div, text, toUnstyled)
import Html.Styled.Attributes exposing (class)
import Html.Styled.Events exposing (..)
import Player
import Tailwind.Utilities as Tw
import Task
import Try
import Url



-- MODEL


type alias Model =
    { key : Nav.Key
    , url : Url.Url
    , gameState : Game.Model
    , consoleState : Console.Model
    }


initGameState : Game.Model
initGameState =
    { roll = []
    , tryToBeat = ( Try.Two, Try.Twos )
    , tableWilds = 0
    , rollState = Game.Init
    , whosTurn = 1
    , history = []
    , quantity = Try.Two
    , value = Try.Threes
    , activePlayers = Data.my_players |> Dict.keys |> Deque.fromList
    , players = Data.my_players
    }


initConsoleState : Console.Model
initConsoleState =
    { consoleHistory = []
    , consoleValue = ""
    , consoleIsVisible = False
    }


init : () -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init flags url key =
    ( { gameState = initGameState
      , consoleState = initConsoleState
      , url = url
      , key = key
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | GameMsg Game.Msg
    | ConsoleMsg Console.Msg
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model, Nav.pushUrl model.key (Url.toString url) )

                Browser.External href ->
                    ( model, Nav.load href )

        UrlChanged url ->
            let
                _ =
                    Debug.log "url changed" url
            in
            ( { model | url = url }
            , Cmd.none
            )

        GameMsg subMsg ->
            case subMsg of
                Game.TryMsg tryMsg ->
                    case tryMsg of
                        Try.ChangeQuantity quant ->
                            ( model.gameState
                                |> (\m -> { m | quantity = quant })
                                |> mergeGameState model
                            , Cmd.none
                            )

                        Try.ChangeValue val ->
                            ( model.gameState
                                |> (\m -> { m | value = val })
                                |> mergeGameState model
                            , Cmd.none
                            )

                Game.ActionMsg actionMsg ->
                    if Game.isValidAction model.gameState.rollState actionMsg then
                        case actionMsg of
                            Game.Roll rollType ->
                                Game.roll rollType model.gameState
                                    |> Tuple.mapBoth
                                        (mergeGameState model)
                                        (Cmd.map (GameMsg << Game.ActionMsg))

                            Game.Pull ->
                                ( Game.pull model.gameState |> mergeGameState model, Cmd.none )

                            Game.Look ->
                                ( Game.look model.gameState |> mergeGameState model, Cmd.none )

                            Game.Pass try ->
                                case Game.pass model.gameState try of
                                    Ok newGameModel ->
                                        let
                                            _ =
                                                Debug.log "pass" newGameModel
                                        in
                                        ( mergeGameState model newGameModel, Cmd.none )

                                    Err e ->
                                        ( mergeConsoleState model (Console.addEntries model.consoleState [ e ]), Cmd.none )

                    else
                        ( mergeConsoleState
                            model
                            (Console.addEntries
                                model.consoleState
                                [ "You can't " ++ Game.decodeAction actionMsg ++ " right now." ]
                            )
                        , Cmd.none
                        )

        ConsoleMsg subMsg ->
            let
                focusCmd =
                    Task.attempt (\_ -> NoOp) (Dom.focus "console")

                ( newConsole, ( newGame, gameMsg ) ) =
                    Console.update subMsg ( model.consoleState, model.gameState )
            in
            ( mergeGameState (mergeConsoleState model newConsole) newGame
            , Cmd.batch [ focusCmd, Cmd.map GameMsg gameMsg ]
            )

        NoOp ->
            ( model, Cmd.none )



-- UPDATE HELPERS


mergeGameState : Model -> Game.Model -> Model
mergeGameState model game =
    { model | gameState = game }


mergeConsoleState : Model -> Console.Model -> Model
mergeConsoleState model console =
    { model | consoleState = console }



-- VIEW


view : Model -> Html Msg
view model =
    let
        _ =
            Debug.log "model" model

        { gameState, consoleState } =
            model

        gameIsOver =
            Deque.length gameState.activePlayers <= 1

        -- UI
        playerStats =
            Player.viewStats gameState.players gameState.whosTurn

        tryHistory =
            Game.viewHistory gameState |> Html.Styled.map GameMsg

        table =
            Game.view gameState |> Html.Styled.map GameMsg

        console =
            Console.view consoleState { onEnter = Console.Submit, onInput = Console.Change } |> Html.Styled.map ConsoleMsg
    in
    div [ class "main" ]
        (global Tw.globalStyles
            :: (if gameIsOver then
                    [ text ("Game over." ++ Player.getName gameState.players (Maybe.withDefault 0 (Deque.first gameState.activePlayers)) ++ " wins!")
                    ]

                else
                    [ logo
                    , playerStats
                    , tryHistory
                    , table
                    , console
                    ]
               )
        )



-- MAIN


main : Program () Model Msg
main =
    Browser.application
        { init = init
        , update = update
        , subscriptions = \_ -> Sub.none
        , view =
            \model ->
                { title = "Dicetron"
                , body = [ view model |> toUnstyled ]
                }
        , onUrlChange = UrlChanged
        , onUrlRequest = LinkClicked
        }
