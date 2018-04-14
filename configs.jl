# This file contains the game configs!
# In debug builds, this file is reloaded in real-time -- every
# `config_reload_time_s` seconds, so you test changes on the fly just by
# modifying these constants.
# In release builds, this file is only included once, during compilation, so
# these values are all defined once as globals.

defaultFontName = "assets/fonts/FiraCode/ttf/FiraCode-Regular.ttf"
defaultFontSize = 26

minWinWidth = Int32(20)  # basically 0.
minWinHeight = Int32(425)  # Prevent getting any smaller than this.

# Menu constants
kPauseSceneTitleFontSize = 40
kPauseSceneSubtitleFontSize = 30

kMenuButtonFontSize = 20
kKeyButtonFontSize = 16
kMenuButtonColor = SDL2.Color(80, 80, 200, 255)
kKeySettingButtonColor = SDL2.Color(185, 55, 48, 255)

kControlsHeaderFontSize = 15

kProgrammedWithJuliaText = ["Programmed with ", " ", " using Julialang ", ""]
kCopyrightNotices = ["Copyright (c) 2018 @nhdalyMadeThis, LLC.",
                     "Theme music copyright http://www.freesfx.co.uk"]

# Game Rendering
kBackgroundColor = SDL2.Color(210,210,210,255)
kFighterColor = SDL2.Color(0xff,0xff,0xff,0x22) # transparent
kWorkerColor = SDL2.Color(0,0,0,0x55) # transparent

kP1Color = SDL2.Color(58, 95, 224, 255)
kP2Color = SDL2.Color(203, 60, 51, 255)

kUIFontSize = 13
kBuildOpsRenderHeight = kUIFontSize + 25

# Unit Attributes

kMaxHealth_Worker = 10
kMaxHealth_Fighter = 20

kAttackDamage_Worker = 1
kAttackDamage_Fighter = 5

kBuildTime_Worker = 5
kBuildTime_Fighter = 10
kBuildCost_Worker = 3
kBuildCost_Fighter = 5

kMoneyPersecPerworker = 1/3.0 # 1 every n secs

# Game constants
kRandPurchaseWorkerPosRange = 100
kRandPurchaseFighterPosRange = 300


paddleSpeed = 1000
paddleTimeToMaxSpeed = 0.15
paddleTimeToDecelerate = 0.05
paddleAccel = paddleSpeed/paddleTimeToMaxSpeed
paddleDeccel = paddleSpeed/paddleTimeToDecelerate
workerSpeed = 350

unitRenderWidth=10
workerRenderWidth=20
healthBarRenderOffset = 2
healthBarRenderWidth = 18; healthBarRenderHeight = 2.5
healthBarColor = SDL2.Color(0,210,0,255)
healthBarOutlineColor = SDL2.Color(0x99,0x99,0x99,0xff)

winningScore = 11


# meta config
config_reload_time_s = 1  # seconds

# Code Testing
#set_health!(p1.units.workers[2], 5)
#println(p1.units.workers[2].health)
