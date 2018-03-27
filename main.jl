println("Start")

# TODO: why does it sometimes hang when you quit.
#  - My _guess_ is it's when it's got a big queue of events that haven't been
#  processed, but that could be unrelated.
#   - this doesn't really make sense: the music stops immediately so it's
#     clearly already hit the "quit" click event, which was the last thing you
#     did, so the queue must be clear.
#  - It happend for >10s on the compiled game, not just thru Atom... HIGH PRIORITY!
#   - And after, cmd-tab was broken til I relaunched the Dock thru Activity Monitor. Yikes!
# TODO: Why does the compiled game sometimes have huge cpu utilization? I
# *think* _this_ is because of having a huge queue of unhandle events. It seems
# to happen when the app is inactive for a while (like if it's maximized in a
# different desktop)

using SDL2

debug = true

# Override SDL libs locations if this script is being compiled for mac .app builds
if get(ENV, "COMPILING_APPLE_BUNDLE", "false") == "true"
    #  (note that you can still change these values b/c no functions have
    #  actually been called yet, and so the original constants haven't been
    #  "compiled in".)
    eval(SDL2, :(libSDL2 = "libSDL2.dylib"))
    eval(SDL2, :(libSDL2_ttf = "libSDL2_ttf.dylib"))
    eval(SDL2, :(libSDL2_mixer = "libSDL2_mixer.dylib"))
    debug = false
end

const assets = "assets"

include("config.jl")
include("timing.jl")
include("objects.jl")
include("display.jl")
include("keyboard.jl")

const kGAME_NAME = "Paddle Battle"
const kSAFE_GAME_NAME = "PaddleBattle"

# Note: These are all Atomics, since they can be modified by the
# windowEventWatcher callback, which can run in another thread!
winWidth, winHeight = Threads.Atomic{Int32}(800), Threads.Atomic{Int32}(600)
minWinWidth = Int32(20)  # basically 0.
minWinHeight = Int32(425)  # Prevent getting any smaller than this.
winWidth_highDPI, winHeight_highDPI = Threads.Atomic{Int32}(800), Threads.Atomic{Int32}(600)
resize_draw_timer = Timer()
function makeWinRenderer()
    global winWidth, winHeight, winWidth_highDPI, winHeight_highDPI

    win = SDL2.CreateWindow(kGAME_NAME,
        Int32(SDL2.WINDOWPOS_CENTERED()), Int32(SDL2.WINDOWPOS_CENTERED()), winWidth[], winHeight[],
        UInt32(SDL2.WINDOW_ALLOW_HIGHDPI|SDL2.WINDOW_OPENGL|SDL2.WINDOW_RESIZABLE|SDL2.WINDOW_SHOWN));
    SDL2.SetWindowMinimumSize(win, minWinWidth, minWinHeight)
    SDL2.AddEventWatch(cfunction(windowEventWatcher, Cint, Tuple{Ptr{Void}, Ptr{SDL2.Event}}), win);
    start!(resize_draw_timer)

    # Find out how big the created window actually was (depends on the system):
    winWidth[], winHeight[], winWidth_highDPI[], winHeight_highDPI[] = getWindowSize(win)
    #cam.w[], cam.h[] = winWidth_highDPI, winHeight_highDPI

    renderer = SDL2.CreateRenderer(win, Int32(-1), UInt32(SDL2.RENDERER_ACCELERATED | SDL2.RENDERER_PRESENTVSYNC))
    SDL2.SetRenderDrawBlendMode(renderer, UInt32(SDL2.BLENDMODE_BLEND))
    return win,renderer
end

# This huge function just handles resize events. I'm not sure why it needs to be
# a callback instead of just the regular pollEvent..
function windowEventWatcher(data_ptr::Ptr{Void}, event_ptr::Ptr{SDL2.Event})::Cint
    global winWidth, winHeight, cam, window_paused, renderer, win
    ev = unsafe_load(event_ptr, 1)
    t = UInt32(0)
    for x in ev._Event[4:-1:1]
        t = t << sizeof(x)*8
        t |= x
    end
    t = SDL2.Event(t)
    if (t == SDL2.WindowEvent)
        event = unsafe_load( Ptr{SDL2.WindowEvent}(pointer_from_objref(ev)) )
        winevent = event.event;  # confusing, but that's what the field is called.
        if (winevent == SDL2.WINDOWEVENT_RESIZED || winevent == SDL2.WINDOWEVENT_SIZE_CHANGED)
            curPaused = window_paused[]
            window_paused[] = 1  # Stop game playing so resizing doesn't cause problems.
            winID = event.windowID
            eventWin = SDL2.GetWindowFromID(winID);
            if (eventWin == data_ptr)
                w,h,w_highDPI,h_highDPI = getWindowSize(eventWin)
                winWidth[], winHeight[] = w, h
                winWidth_highDPI[], winHeight_highDPI[] = w_highDPI, h_highDPI
                cam.w[], cam.h[] = winWidth_highDPI[], winHeight_highDPI[]
                recenterButtons!()
            end
            #if elapsed(resize_draw_timer) > 0.005
                render(sceneStack[end], renderer, eventWin)
                SDL2.GL_SwapWindow(eventWin);
                #start!(resize_draw_timer)
            #end
            window_paused[] = curPaused  # Allow game to resume now that resizing is done.
        elseif (winevent == SDL2.WINDOWEVENT_FOCUS_LOST || winevent == SDL2.WINDOWEVENT_HIDDEN || winevent == SDL2.WINDOWEVENT_MINIMIZED)
            # Stop game playing so resizing doesn't cause problems.
            if !debug  # For debug builds, allow editing while playing
                window_paused[] = 1
            end
        elseif (winevent == SDL2.WINDOWEVENT_FOCUS_GAINED || winevent == SDL2.WINDOWEVENT_SHOWN)
            window_paused[] = 0
        end
        # Note that window events pause the game, so at the end of any window
        # event, restart the timer so it doesn't have a HUGE frame.
        start!(timer)
    end
    return 0
end

function getWindowSize(win)
    w,h,w_highDPI,h_highDPI = Int32[0],Int32[0],Int32[0],Int32[0]
    SDL2.GetWindowSize(win, w, h)
    SDL2.GL_GetDrawableSize(win, w_highDPI, h_highDPI)
    return w[],h[],w_highDPI[],h_highDPI[]
end

# Having a QuitException is useful for testing, since an exception will simply
# pause the interpreter. For release builds, the catch() block will call quitSDL().
struct QuitException <: Exception end

function quitSDL(win)
    # Need to close the callback before quitting SDL to prevent it from hanging
    # https://github.com/n0name/2D_Engine/issues/3
    SDL2.DelEventWatch(cfunction(windowEventWatcher, Cint, Tuple{Ptr{Void}, Ptr{SDL2.Event}}), win);
    SDL2.Mix_CloseAudio()
    SDL2.TTF_Quit()
    SDL2.Quit()
end

# Game State Globals
renderer = win = nothing
paddleA = Paddle(WorldPos(0,200), Vector2D(0,0), 200)
paddleB = Paddle(WorldPos(0,-200), Vector2D(0,0), 200)
ball = Ball(WorldPos(0,0), Vector2D(0,-ballSpeed))
cam = nothing
scoreA = 0
scoreB = 0
paused_ = true # start paused to show the initial menu.
paused = Ref(paused_)
window_paused = Threads.Atomic{UInt8}(0) # Whether or not the game should be running (if lost focus)
game_started_ = true # start paused to show the initial menu.
game_started = Ref(game_started_)
playing_ = true
playing = Ref(playing_)
debugText = false
audioEnabled = true
last_10_frame_times = [1.]
timer = Timer()
i = 1

sceneStack = []  # Used to keep track of the current scene
function runSceneGameLoop(scene, renderer, win, inSceneVar::Ref{Bool})
    global last_10_frame_times, i
    push!(sceneStack, scene)
    start!(timer)
    while (inSceneVar[])
        # Don't run if game is paused by system (resizing, lost focus, etc)
        while window_paused[] != 0  # Note that this will be fixed by windowEventWatcher
            _ = pollEvent!()
            sleep(0.1)
        end
        # Reload config for debug
        if (debug) reloadConfigsFile() end

        # Handle Events
        hadEvents = true
        while hadEvents
            e,hadEvents = pollEvent!()
            t = getEventType(e)
            handleEvents!(scene,e,t)
        end

        # Render
        render(scene, renderer, win)
        SDL2.RenderPresent(renderer)

        # Update
        dt = elapsed(timer)
        # Don't let the game proceed at fewer than this frames per second. If an
        # update takes too long, allow the game to actually slow, rather than
        # having too big of frames.
        min_fps = 20.0
        dt = min(dt, 1./min_fps)
        start!(timer)
        last_10_frame_times = push!(last_10_frame_times, dt)
        if length(last_10_frame_times) > 10; shift!(last_10_frame_times) ; end
        if (debugText) renderFPS(renderer,last_10_frame_times) end

        performUpdates!(scene, dt)
        #sleep(0.01)

        if (playing[] == false)
            throw(QuitException())
        end

        i += 1
    end
    pop!(sceneStack)
end
function performUpdates!(scene, dt) end  # default


function pollEvent!()
    #SDL2.Event() = [SDL2.Event(NTuple{56, Uint8}(zeros(56,1)))]
    SDL_Event() = Array{UInt8}(zeros(56))
    e = SDL_Event()
    success = (SDL2.PollEvent(e) != 0)
    return e,success
end
function getEventType(e::Array{UInt8})
    # HAHA This is still pretty janky, but I guess that's all you can do w/ unions.
    bitcat(UInt32, e[4:-1:1])
end
function getEventType(e::SDL2.Event)
    e._Event[1]
end

function bitcat(outType::Type{T}, arr)::T where T<:Number
    out = zero(outType)
    for x in arr
        out = out << sizeof(x)*8
        out |= x
    end
    out
end

type GameScene end

function handleEvents!(scene::GameScene, e,t)
    global playing,paused
    # Handle Events
    if (t == SDL2.KEYDOWN || t == SDL2.KEYUP);  handleKeyPress(e,t);
    elseif (t == SDL2.QUIT);  playing[] = false;
    end

    if (paused[])
         pause!(timer)
         enterPauseGameLoop(renderer,win)
         unpause!(timer)
    end
end


function render(scene::GameScene, renderer, win)
    global ball,scoreA,scoreB,last_10_frame_times,paused,playing

    color = kBackgroundColor
    SDL2.SetRenderDrawColor(renderer, Int64(color.r), Int64(color.g), Int64(color.b), Int64(color.a))
    SDL2.RenderClear(renderer)

    renderScore(renderer)
    render(paddleA, cam, renderer)
    render(paddleB, cam, renderer)

    render(ball, cam, renderer)
end

function performUpdates!(scene::GameScene, dt)
    global ball, paddleA, paddleB, scoreB, scoreA
    #if didCollide(ball, paddleA, dt);
    #     ball.pos = ball.pos - ball.vel  # undo update
    #     collide!(ball, paddleA);
    #end
    #if didCollide(ball, paddleB, dt);
    #     ball.pos = ball.pos - ball.vel  # undo update
    #     collide!(ball, paddleB);
    #end
    if willCollide(ball, paddleA, dt); collide!(ball, paddleA); end
    if willCollide(ball, paddleB, dt); collide!(ball, paddleB); end
    if (willCollide(ball, paddleA,dt) || willCollide(ball, paddleB,dt))
        # STUCK GOING TOO FAST
        slowed_dt = dt
        while (willCollide(ball, paddleA, slowed_dt) || willCollide(ball, paddleB, slowed_dt))
            slowed_dt *= .1
        end
        update!(ball, slowed_dt)
    else
        update!(ball, dt)
    end
    update!(paddleA, paddleAKeys, dt)
    update!(paddleB, paddleBKeys, dt)

    if (scoreA >= winningScore)  enterWinnerGameLoop(renderer,win, "Player 1")
    elseif (scoreB >= winningScore)  enterWinnerGameLoop(renderer,win, "Player 2")
    end
end

function enterWinnerGameLoop(renderer,win, winnerName)
    # Reset the buttons to the beginning of the game.
    buttons[:bRestart].enabled = false # Nothing to restart
    buttons[:bNewContinue].text = "New Game"
    global paused,game_started; paused[] = true; game_started[] = false;

    # Move the ball off-screen here so it doesn't show up on the winning
    # player screen.
    ball.pos = WorldPos(winWidth[] + 20, 0);

    scene = PauseScene("$winnerName wins!!", "")
    runSceneGameLoop(scene, renderer, win, paused)

    # When the pause scene returns, reset the game before starting.
    resetGame()
end
function resetGame()
    global scoreA,scoreB
    scoreB = scoreA = 0
    ball.pos = WorldPos(0,0)
    ball.vel = Vector2D(0,rand([ballSpeed,-ballSpeed]))

    paddleA.pos = WorldPos(0,200)
    paddleB.pos = WorldPos(0,-200)
end

mutable struct KeyControls
    rightDown::Bool
    leftDown::Bool
    KeyControls() = new(false,false)
end
const paddleAKeys = KeyControls()
const paddleBKeys = KeyControls()
mutable struct GameControls
    escapeDown::Bool
    GameControls() = new(false)
end
const gameControls = GameControls()

getKeySym(e) = UInt32(parse("0b"*join(map(bits,  e[24:-1:21]))))
function handleKeyPress(e,t)
    global paused,debugText
    keySym = getKeySym(e)
    keyDown = (t == SDL2.KEYDOWN)
    if (keySym == keySettings[:keyALeft])
        paddleAKeys.leftDown = keyDown
    elseif (keySym == keySettings[:keyARight])
        paddleAKeys.rightDown = keyDown
    elseif (keySym == keySettings[:keyBLeft])
        paddleBKeys.leftDown = keyDown
    elseif (keySym == keySettings[:keyBRight])
        paddleBKeys.rightDown = keyDown
    elseif (keySym == SDL2.SDLK_ESCAPE)
        if (!gameControls.escapeDown && keyDown)
            if game_started[]  # Escape shouldn't start the game.
                paused[] = !paused[]
            end
        end
        gameControls.escapeDown = keyDown
    elseif (keySym == SDL2.SDLK_BACKQUOTE)
        keyDown && (debugText = !debugText)
    end
end

buttons = Dict([
    # This button is disabled until the game starts.
    :bRestart =>
        MenuButton(false, UIPixelPos(0,0), 200, 30, "New Game",
            ()->(resetGame(); buttons[:bNewContinue].callBack();))
    # Note that this text changes to "Continue" after first press.
    :bNewContinue =>
        MenuButton(true, UIPixelPos(0,0), 200, 30, "New Game",
               ()->(global paused,game_started,buttons;
                    paused[] = false; game_started[] = true;
                    buttons[:bNewContinue].text = "Continue"; # After starting game
                    buttons[:bRestart].enabled = true;        # After starting game
                    ))
    :bSoundToggle =>
        CheckboxButton(true,
            MenuButton(true, UIPixelPos(0,0), 200, 30, "Sound on/off",
                (enabled)->(toggleAudio(enabled)))
            )
    :bQuit =>
        MenuButton(true, UIPixelPos(0,0), 200, 30, "Quit",
            ()->(global paused, playing; paused[] = playing[] = false;))

     # Key controls buttons
    :keyALeft =>
        KeyButton(true, UIPixelPos(0,0), 120, 20, keyDisplayNames[keySettings[:keyALeft]],
               ()->(tryChangingKeySettingButton(:keyALeft)))
    :keyARight =>
        KeyButton(true, UIPixelPos(0,0), 120, 20, keyDisplayNames[keySettings[:keyARight]],
               ()->(tryChangingKeySettingButton(:keyARight)))
    :keyBLeft =>
        KeyButton(true, UIPixelPos(0,0), 120, 20, keyDisplayNames[keySettings[:keyBLeft]],
               ()->(tryChangingKeySettingButton(:keyBLeft)))
    :keyBRight =>
        KeyButton(true, UIPixelPos(0,0), 120, 20, keyDisplayNames[keySettings[:keyBRight]],
               ()->(tryChangingKeySettingButton(:keyBRight)))

    :bResetDefaultKeys =>
        KeyButton(false, UIPixelPos(0,0), 240, 30, "Reset Default Controls",
               ()->(resetDefaultKeys()))
  ])
paddleAControlsX() = screenCenterX()-260
paddleBControlsX() = screenCenterX()+260
function recenterButtons!()
    global buttons
    buttons[:bRestart].pos     = screenOffsetFromCenter(0,-25)
    buttons[:bNewContinue].pos = screenOffsetFromCenter(0,9)
    buttons[:bSoundToggle].button.pos = screenOffsetFromCenter(0,43)
    buttons[:bQuit].pos        = screenOffsetFromCenter(0,77)
    buttons[:keyALeft].pos    = UIPixelPos(paddleAControlsX(), winHeight[]-147)
    buttons[:keyARight].pos   = UIPixelPos(paddleAControlsX(), winHeight[]-122)
    buttons[:keyBLeft].pos    = UIPixelPos(paddleBControlsX(), winHeight[]-147)
    buttons[:keyBRight].pos   = UIPixelPos(paddleBControlsX(), winHeight[]-122)
    buttons[:bResetDefaultKeys].pos   = UIPixelPos(screenCenterX(), winHeight[]-102)
end
function toggleAudio(enabled)
    global audioEnabled;
    audioEnabled = enabled;
    if (audioEnabled) SDL2.Mix_ResumeMusic()
    else  SDL2.Mix_PauseMusic()
    end
end
type PauseScene
    titleText::String
    subtitleText::String
end
function enterPauseGameLoop(renderer,win)
    global paused
    scene = PauseScene("$kGAME_NAME", "Main Menu")
    runSceneGameLoop(scene, renderer, win, paused)
end
function handleEvents!(scene::PauseScene, e,t)
    global playing,paused
    # Handle Events
    if (t == SDL2.KEYDOWN || t == SDL2.KEYUP);  handleKeyPress(e,t);
    elseif (t == SDL2.MOUSEBUTTONUP || t == SDL2.MOUSEBUTTONDOWN)
        b = handleMouseClickButton!(e,t);
        if (b != nothing); run(b); end
    elseif (t == SDL2.QUIT);
        playing[]=false; paused[]=false;
    end
end

heartIcon = nothing
jlLogoIcon = nothing
function render(scene::PauseScene, renderer, win)
    global heartIcon, jlLogoIcon
    if heartIcon == nothing || jlLogoIcon == nothing
        heart_surface = SDL2.LoadBMP("assets/heart.bmp")
        heartIcon = SDL2.CreateTextureFromSurface(renderer, heart_surface) # Will be C_NULL on failure.
        SDL2.FreeSurface(heart_surface)
        jlLogo_surface = SDL2.LoadBMP("assets/jllogo.bmp")
        jlLogoIcon = SDL2.CreateTextureFromSurface(renderer, jlLogo_surface) # Will be C_NULL on failure.
        SDL2.FreeSurface(jlLogo_surface)
    end
    screenRect = SDL2.Rect(0,0, cam.w[], cam.h[])
    # First render the scene under the pause menu so it looks like the pause is over it.
    if (length(sceneStack) > 1) render(sceneStack[end-1], renderer, win) end
    color = kBackgroundColor
    SDL2.SetRenderDrawColor(renderer, Int64(color.r), Int64(color.g), Int64(color.b), 200) # transparent
    SDL2.RenderFillRect(renderer, Ref(screenRect))
    renderText(renderer, cam, scene.titleText, screenOffsetFromCenter(0,-149)
               ; fontSize=kPauseSceneTitleFontSize)
    renderText(renderer, cam, scene.subtitleText, screenOffsetFromCenter(0,-109); fontSize = kPauseSceneSubtitleFontSize)
    for b in values(buttons)
        render(b, cam, renderer)
    end
    renderText(renderer, cam, "Player 1 Controls", UIPixelPos(paddleAControlsX(),winHeight[]-169); fontSize = kControlsHeaderFontSize)
    renderText(renderer, cam, "Player 2 Controls", UIPixelPos(paddleBControlsX(),winHeight[]-169); fontSize = kControlsHeaderFontSize)
    renderText(renderer, cam, "Theme music copyright http://www.freesfx.co.uk", UIPixelPos(screenCenterX(), winHeight[] - 10);
          fontName="assets/fonts/FiraCode/ttf/FiraCode-Regular.ttf",
          fontSize=10)

    _, heartPos, _, jlLogoPos =
      hcat_render_text(["Programmed with ", " ", " in Julia ", ""], renderer, cam,
         0, UIPixelPos(screenCenterX(), winHeight[] - 28);
          fontName="assets/fonts/FiraCode/ttf/FiraCode-Regular.ttf",
          fontSize=16)
    render(heartIcon, heartPos, cam, renderer; size=UIPixelPos(16,16))
    render(jlLogoIcon, jlLogoPos, cam, renderer; size=UIPixelPos(16,16))
end

function renderScore(renderer)
    # Size the text with a single-digit score so it doesn't move when score hits double-digits.
    txtW,_ = sizeText(cam, "Player 1: 0", defaultFontName, defaultFontSize)
    hcat_render_text(["Player 1: $scoreA","Player 2: $scoreB"], renderer, cam,
         100, UIPixelPos(screenCenterX(), 20)
         ; fixedWidth=txtW)
end
function renderFPS(renderer,last_10_frame_times)
    fps = Int(floor(1./mean(last_10_frame_times)))
    txt = "FPS: $fps"
    renderText(renderer, cam, txt, UIPixelPos(winWidth[]*1/5, 200))
end

clickedButton = nothing
function handleMouseClickButton!(e, clickType)
    global clickedButton
    mx = Int64(parse("0b"*join(map(bits,  e[24:-1:21]))));
    my = Int64(parse("0b"*join(map(bits,  e[28:-1:25]))));
    didClickButton = false
    for b in values(buttons)
        if mouseOnButton(UIPixelPos(mx,my),b,cam)
            if (clickType == SDL2.MOUSEBUTTONDOWN)
                clickedButton = b
                didClickButton = true
                break
            elseif clickedButton == b && clickType == SDL2.MOUSEBUTTONUP
                clickedButton = nothing
                didClickButton = true
                return b
            end
        end
    end
    if clickedButton != nothing && clickType == SDL2.MOUSEBUTTONUP && didClickButton == false
        clickedButton = nothing
    end
    return nothing
end

function mouseOnButton(m::UIPixelPos, b::CheckboxButton, cam)
    return mouseOnButton(m, b.button, cam)
end
function mouseOnButton(m::UIPixelPos, b::AbstractButton, cam)
    if (!b.enabled) return false end
    topLeft = UIPixelPos(b.pos.x - b.w/2., b.pos.y - b.h/2.)
    if m.x > topLeft.x && m.x <= topLeft.x + b.w &&
        m.y > topLeft.y && m.y <= topLeft.y + b.h
        return true
    end
    return false
end

function change_dir_if_bundle()
    # julia_cmd() shows how this julia process was invoked.
    cmd_strings = Base.shell_split(string(Base.julia_cmd()))
    # The first string is the full path to this executable.
    full_binary_name = cmd_strings[1][2:end] # (remove leading backtick)
    if is_apple()
        # On Apple devices, if this is running inside a .app bundle, it starts
        # us with pwd="$HOME". Change dir to the Resources dir instead.
        # Can tell if we're in a bundle by what the full_binary_name ends in.
        m = match(r".app/Contents/MacOS/[^/]+$", full_binary_name)
        if m != nothing
            resources_dir = full_binary_name[1:findlast("/MacOS", full_binary_name)[1]-1]*"/Resources"
            cd(resources_dir)
        end
    end
    println("new pwd: $(pwd())")
end
function load_audio_files()
    global pingSound, scoreSound, badKeySound
    pingSound = SDL2.Mix_LoadWAV( "$assets/ping.wav" );
    scoreSound = SDL2.Mix_LoadWAV( "$assets/score.wav" );
    badKeySound = SDL2.Mix_LoadWAV( "$assets/ping.wav" );
end

Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
    global renderer, win, paused,game_started, cam
    win = nothing
    try
        SDL2.init()
        change_dir_if_bundle()
        init_prefspath()
        load_prefs_backup()
        load_audio_files()
        music = SDL2.Mix_LoadMUS( "$assets/music.wav" );
        win,renderer = makeWinRenderer()
        cam = Camera(WorldPos(0,0),
                     Threads.Atomic{Int32}(winWidth_highDPI[]),
                     Threads.Atomic{Int32}(winHeight_highDPI[]))
        global paused,game_started; paused[] = true; game_started[] = false;
        # Warm up
        for i in 1:3
            pollEvent!()
            SDL2.SetRenderDrawColor(renderer, 200, 200, 200, 255)
            SDL2.RenderClear(renderer)
            SDL2.RenderPresent(renderer)
            #sleep(0.01)
        end
        audioEnabled && SDL2.Mix_PlayMusic( music, Int32(-1) )
        recenterButtons!()
        resetGame();  # Initialize game stuff.
        playing[] = paused[] = true
        scene = GameScene()
        runSceneGameLoop(scene, renderer, win, playing)
    catch e
        if isa(e, QuitException)
            quitSDL(win)
        else
            throw(e)  # Every other kind of exception
        end
    end
        return 0
end

#julia_main([""])
