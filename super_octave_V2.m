% ========================================================================
% PROGRAM     : super_octave_VF.m
% GOAL        : Run and jump through 5 levels, stomp enemies, collect coins, reach the flag
% CONTEXT     : Octave course project, 2.5D platformer
% AUTHORS     : [Loann RAVEL] (...), [Loïc LOBLOT] (...)
% DATE        : [2026-10-1]
% OCTAVE      : version [2.50.1] / CODE VERSION : 2.0
% SOURCES     : [AI used (Claude, ChatGPT) for code structure, checked and adapted by authors];
%               no image, no sound, no word list
%
% GAME COMPONENTS : player (small pink brain), ground, blocks, holes, enemies, coins, flag
% VARIABLES       : px, py (player position), vy (vertical speed), lives, totalScore, level,
%                   S (solid rectangles), enX (enemy positions), coins, camX (camera),
%                   keys (state of the left/right keys)
% MAIN LOOP       : read keyboard, move player, gravity, collisions, enemies, coins, camera, redraw
% ACROSS TRIALS   : levels are generated (harder each time), new random seed at each replay,
%                   best score is kept, results are saved in results.txt
% RULES           : 5 lives for the whole game, falling in a hole or touching an enemy = -1 life,
%                   jumping on an enemy kills it (+100), coin = +10, flag = next level
% WAYS TO MOVE    : LEFT/RIGHT arrows (or A/D) to run, UP arrow (or SPACE or W) to jump
% ========================================================================
1;  % script file marker (needed because functions are defined below)

% ---- Function: build a level (harder when level increases) -------------
function [S, coins, enemies, segStarts, goalX, worldLength] = build_level(level, runSeed)
  rand('state', runSeed * 10 + level);      % same level during a run, new levels at each replay
  nSeg      = 4 + 2 * level;                % number of ground pieces
  S         = zeros(0, 4);                  % solids: [x1 y1 x2 y2]
  coins     = zeros(0, 2);                  % coins: [x y]
  enemies   = zeros(0, 3);                  % enemies: [xmin xmax speed]
  segStarts = zeros(1, nSeg);               % start of each ground piece (checkpoints)
  x = 0;
  for s = 1:nSeg
    if s == 1
      segLen = 45;                          % safe first piece
    else
      segLen = 40 - 3 * level + 10 * rand();% ground pieces get shorter
    endif
    segStarts(s) = x;
    S(end+1, :) = [x, -10, x + segLen, 0];  % ground piece
    hasBlock = false;
    if level >= 2 && s > 1 && rand() < 0.5
      bx = x + segLen * (0.35 + 0.3 * rand());
      bh = 3 + 2 * rand() + (level >= 4) * 2;
      S(end+1, :) = [bx, 0, bx + 5, bh];    % block to jump over
      hasBlock = true;
    endif
    if s > 1 && ~hasBlock && rand() < 0.35 + 0.1 * level
      enemies(end+1, :) = [x + 4, x + segLen - 4, 0.15 + 0.07 * level];  % faster enemies
    endif
    coinY = 5 + 4 * hasBlock;               % coins above blocks are higher
    coins(end+1:end+3, :) = [x + segLen * [0.25; 0.5; 0.75], [coinY; coinY; coinY]];
    if s < nSeg
      gap = 6 + 3.2 * level + 2 * rand();   % holes get wider
      gx  = x + segLen;
      if level <= 2 && rand() < 0.5
        S(end+1, :) = [gx + gap/2 - 3, 5, gx + gap/2 + 3, 6.5];  % stepping stone (easy levels)
      endif
      coins(end+1:end+3, :) = [gx + gap * [0.25; 0.5; 0.75], [11; 12; 11]];
      x = gx + gap;
    else
      x = x + segLen;
    endif
  endfor
  goalX       = x - 8;                      % flag position
  worldLength = x + 5;
endfunction

% ---- Function: a key is pressed ----------------------------------------
% Octave names the arrow keys 'leftarrow', 'rightarrow', 'uparrow'
function key_press(fig, evt)
  keys = getappdata(fig, 'keys');           % [left right] pressed state
  k    = lower(evt.Key);                    % name of the key, in lower case
  if any(strcmp(k, {'leftarrow', 'left', 'a'}))
    keys(1) = true;                         % run left
  elseif any(strcmp(k, {'rightarrow', 'right', 'd'}))
    keys(2) = true;                         % run right
  elseif any(strcmp(k, {'uparrow', 'up', 'space', ' ', 'w'}))
    setappdata(fig, 'jumpRequested', true); % jump asked
  endif
  setappdata(fig, 'keys', keys);
endfunction

% ---- Function: a key is released ---------------------------------------
function key_release(fig, evt)
  keys = getappdata(fig, 'keys');
  k    = lower(evt.Key);
  if any(strcmp(k, {'leftarrow', 'left', 'a'}))
    keys(1) = false;
  elseif any(strcmp(k, {'rightarrow', 'right', 'd'}))
    keys(2) = false;
  endif
  setappdata(fig, 'keys', keys);
endfunction

% ---- Function: display a text screen (rules, results) ------------------
function show_screen(ax, message)
  set(get(ax, 'Parent'), 'Color', [0.05 0.05 0.2]);  % dark background
  cla(ax);
  axis(ax, [0 100 0 100]);
  axis(ax, 'off');
  text(ax, 50, 50, message, 'HorizontalAlignment', 'center', ...
       'Color', 'w', 'FontSize', 14);
  drawnow();
endfunction

% ---- Function: ask the player to replay --------------------------------
function answer = ask_replay()
  choice = input('Play again? (y/n): ', 's');
  answer = strcmpi(choice, 'y');
endfunction

% ---- Clean workspace ----------------------------------------------------
clear; clc; close all;

% ---- Parameters ---------------------------------------------------------
nLevels     = 5;       % number of levels
startLives  = 5;       % lives for the whole game
playerW     = 3;       % player width
playerH     = 4;       % player height
enemyW      = 3;       % enemy width
enemyH      = 3;       % enemy height
enemyY      = 0;       % enemies walk on the ground
gravity     = 0.1;     % gravity (units per frame)
jumpSpeed   = 1.6;     % initial speed of a jump
maxSpeed    = 0.8;     % running speed (lower = slower)
framePause  = 0.025;   % pause between frames (s), increase it if the game is too fast
skyColors   = [0.45 0.75 1.00; 0.55 0.85 0.65; 0.95 0.70 0.45; 0.55 0.35 0.65; 0.10 0.10 0.25];
bestScore   = 0;       % best score over all games
keepPlaying = true;    % replay flag

% ---- Brain shape (relative to the player position) ----------------------
angle  = linspace(0, 2*pi, 120);                           % angles around the brain
bumps  = 1 + 0.07 * sin(9 * angle);                        % small bumps = brain folds
brainX = 0.46 * playerW * bumps .* cos(angle);             % outline x (relative to px)
brainY = 0.46 * playerH * bumps .* sin(angle) + playerH/2; % outline y (relative to py)
foldT  = linspace(0, 1, 30);                               % parameter of the central fold
foldX  = 0.10 * playerW * sin(4 * pi * foldT);             % wavy line x
foldY  = playerH * (0.12 + 0.76 * foldT);                  % wavy line y

% ---- Figure (resizable) and keyboard callbacks --------------------------
try
  graphics_toolkit('qt');                   % the qt toolkit is needed to read the keyboard
catch
  % keep the default toolkit if qt is not available
end_try_catch
fig = figure('Name', 'Super Octave', 'NumberTitle', 'off');
ax  = axes('Parent', fig, 'Position', [0 0 1 1]);
setappdata(fig, 'keys', [false false]);     % [left right] pressed state
setappdata(fig, 'jumpRequested', false);
set(fig, 'KeyPressFcn',   @(src, evt) key_press(src, evt));    % key pressed
set(fig, 'KeyReleaseFcn', @(src, evt) key_release(src, evt));  % key released

while keepPlaying && ishandle(fig)

  % ---- New game: reset everything ---------------------------------------
  runSeed    = randi(1000);                 % new seed = new levels at each replay
  level      = 1;
  lives      = startLives;
  totalScore = 0;

  show_screen(ax, {'SUPER OCTAVE', '', ...
    'Use the LEFT / RIGHT arrows (or A / D) to run.', ...
    'Press the UP arrow (or SPACE or W) to jump.', ...
    'Jump on enemies to kill them (+100), collect coins (+10).', ...
    'Falling in a hole or touching an enemy = -1 life.', ...
    sprintf('Reach the flag in each of the %d levels with %d lives.', nLevels, startLives), ...
    '', 'Press any key to start'});
  waitforbuttonpress();

  while level <= nLevels && lives > 0 && ishandle(fig)

    % ---- Build the level ------------------------------------------------
    [S, coins, enemies, segStarts, goalX, worldLength] = build_level(level, runSeed);
    nCoins    = size(coins, 1);
    nEnemies  = size(enemies, 1);
    coinAlive = true(1, nCoins);
    enMin     = enemies(:, 1)';
    enMax     = enemies(:, 2)';
    enSpeed   = enemies(:, 3)';
    enX       = enMin + rand(1, nEnemies) .* (enMax - enMin);  % random start position
    enDir     = ones(1, nEnemies);          % walking direction (+1 / -1)
    enAlive   = true(1, nEnemies);

    show_screen(ax, {sprintf('LEVEL %d / %d', level, nLevels), '', 'Get ready...'});
    pause(1.5);

    % ---- Draw the level (pseudo-3D: shadow behind each block) -------------
    set(fig, 'Color', skyColors(level, :));
    cla(ax); axis(ax, [0 100 -12 48]); axis(ax, 'off'); hold(ax, 'on');
    for k = 1:size(S, 1)
      w = S(k,3) - S(k,1);
      h = S(k,4) - S(k,2);
      rectangle('Parent', ax, 'Position', [S(k,1) + 1.2, S(k,2) - 1.2, w, h], ...
                'FaceColor', [0.15 0.1 0.05], 'EdgeColor', 'none');   % shadow = depth effect
      if S(k,2) == -10
        rectangle('Parent', ax, 'Position', [S(k,1), S(k,2), w, h], ...
                  'FaceColor', [0.55 0.35 0.15], 'EdgeColor', 'k');   % ground
        rectangle('Parent', ax, 'Position', [S(k,1), -0.8, w, 0.8], ...
                  'FaceColor', [0.2 0.7 0.2], 'EdgeColor', 'none');   % grass
      else
        rectangle('Parent', ax, 'Position', [S(k,1), S(k,2), w, h], ...
                  'FaceColor', [0.6 0.6 0.65], 'EdgeColor', 'k');     % block / stone
      endif
    endfor
    rectangle('Parent', ax, 'Position', [goalX, 0, 0.8, 14], 'FaceColor', [0.9 0.9 0.9]);  % flag pole
    patch('Parent', ax, 'XData', [goalX + 0.8, goalX + 7, goalX + 0.8], ...
          'YData', [14, 11.5, 9], 'FaceColor', [1 0.1 0.1]);                              % flag
    hCoin = zeros(1, nCoins);
    for k = 1:nCoins
      hCoin(k) = rectangle('Parent', ax, 'Position', [coins(k,1) - 1, coins(k,2) - 1, 2, 2], ...
                           'Curvature', [1 1], 'FaceColor', [1 0.85 0], 'EdgeColor', 'k');
    endfor
    hEn = zeros(1, nEnemies);
    for k = 1:nEnemies
      hEn(k) = rectangle('Parent', ax, 'Position', [enX(k) - enemyW/2, enemyY, enemyW, enemyH], ...
                         'Curvature', [0.4 0.4], 'FaceColor', [0.6 0.2 0.1], 'EdgeColor', 'k');
    endfor
    hPlayer = patch('Parent', ax, 'XData', 5 + brainX, 'YData', brainY, ...
                    'FaceColor', [1 0.65 0.75], 'EdgeColor', [0.6 0.1 0.3], ...
                    'LineWidth', 1.5);                   % pink brain body
    hFold   = line('Parent', ax, 'XData', 5 + foldX, 'YData', foldY, ...
                   'Color', [0.6 0.1 0.3], 'LineWidth', 1.5);  % central fold line
    hInfo = text(ax, 2, 46, '', 'Color', 'w', 'FontSize', 12, ...
                 'BackgroundColor', [0.1 0.1 0.1], 'VerticalAlignment', 'top');

    % ---- Reset the player for this level ------------------------------------
    px = 5; py = 0; vy = 0;                 % position and vertical speed
    onGround = false;
    invuln   = 0;                           % invulnerability frames after a hit
    camX     = 0;                           % camera position
    status   = 'playing';
    setappdata(fig, 'jumpRequested', false);
    setappdata(fig, 'keys', [false false]); % avoid a key stuck from the previous level

    % ---- Main loop of one level ---------------------------------------------
    while strcmp(status, 'playing') && ishandle(fig)
      died = false;

      % Input: run with the left/right keys
      keys = getappdata(fig, 'keys');       % [left right]
      vx   = maxSpeed * (double(keys(2)) - double(keys(1)));  % +right, -left, 0 if none or both

      % Input: jump (only if standing on something)
      if getappdata(fig, 'jumpRequested')
        if onGround
          vy = jumpSpeed;
          onGround = false;
        endif
        setappdata(fig, 'jumpRequested', false);
      endif

      % Horizontal movement and collisions with solids
      pxNew = px + vx;
      hitX  = find(pxNew + playerW/2 > S(:,1) & pxNew - playerW/2 < S(:,3) & ...
                   py + playerH > S(:,2) & py < S(:,4) - 1e-6);
      for k = hitX(:)'
        if vx > 0
          pxNew = S(k,1) - playerW/2;       % stopped by the left side of the solid
        elseif vx < 0
          pxNew = S(k,3) + playerW/2;       % stopped by the right side of the solid
        endif
      endfor
      px = max(pxNew, playerW/2);           % left wall of the world

      % Vertical movement (gravity) and collisions with solids
      vy    = vy - gravity;
      pyNew = py + vy;
      onGround = false;
      if vy < 0
        land = find(px + playerW/2 > S(:,1) & px - playerW/2 < S(:,3) & ...
                    py >= S(:,4) - 1e-6 & pyNew < S(:,4));
        if ~isempty(land)
          pyNew = max(S(land, 4));          % land on the highest solid
          onGround = true;
          vy = 0;
        endif
      elseif vy > 0
        bump = find(px + playerW/2 > S(:,1) & px - playerW/2 < S(:,3) & ...
                    py + playerH <= S(:,2) + 1e-6 & pyNew + playerH > S(:,2));
        if ~isempty(bump)
          pyNew = min(S(bump, 2)) - playerH;% head hits a solid
          vy = 0;
        endif
      endif
      py = pyNew;

      % Enemies: walk back and forth
      enX  = enX + enDir .* enSpeed;
      turn = enX > enMax | enX < enMin;
      enDir(turn) = -enDir(turn);
      enX  = min(max(enX, enMin), enMax);

      % Enemies: collision with the player
      if invuln > 0
        invuln = invuln - 1;
      endif
      hitE = find(enAlive & abs(px - enX) < (playerW + enemyW)/2 & ...
                  py < enemyY + enemyH & py + playerH > enemyY);
      for k = hitE(:)'
        if vy < 0 && py > enemyY + enemyH * 0.4
          enAlive(k) = false;               % stomp: enemy killed
          vy = 0.6 * jumpSpeed;             % small bounce
          totalScore = totalScore + 100;
        elseif invuln == 0
          died = true;                      % touched from the side
        endif
      endfor

      % Coins
      coinHit = find(coinAlive & abs(coins(:,1)' - px) < 3 & abs(coins(:,2)' - (py + playerH/2)) < 4);
      for k = coinHit(:)'
        coinAlive(k) = false;
        set(hCoin(k), 'Visible', 'off');
        totalScore = totalScore + 10;
      endfor

      % Falling in a hole
      if py < -25
        died = true;
      endif

      % Death: lose a life and go back to the last checkpoint
      if died
        lives = lives - 1;
        if lives == 0
          status = 'lost';
        else
          px = max(segStarts(segStarts <= px)) + 2;   % start of the last ground piece
          py = 0; vy = 0;
          invuln = 60;
        endif
      endif

      % Flag reached
      if px >= goalX
        status = 'won';
      endif

      % Camera and graphics
      camX = min(max(px - 30, 0), worldLength - 100);
      set(ax, 'XLim', [camX camX + 100]);
      set(hPlayer, 'XData', px + brainX, 'YData', py + brainY);  % move the brain
      set(hFold,   'XData', px + foldX,  'YData', py + foldY);   % move the fold line
      if invuln > 0 && mod(floor(invuln / 5), 2) == 0
        set([hPlayer hFold], 'Visible', 'off');  % blinking when invulnerable
      else
        set([hPlayer hFold], 'Visible', 'on');
      endif
      for k = 1:nEnemies
        if enAlive(k)
          set(hEn(k), 'Position', [enX(k) - enemyW/2, enemyY, enemyW, enemyH]);
        else
          set(hEn(k), 'Visible', 'off');
        endif
      endfor
      set(hInfo, 'Position', [camX + 2, 46, 0], 'String', ...
          sprintf('Level %d/%d   Lives: %d   Score: %d', level, nLevels, lives, totalScore));
      drawnow();
      pause(framePause);
    endwhile

    if ~ishandle(fig)                       % figure closed by the player: stop
      break;
    endif

    % ---- End of the level ---------------------------------------------------
    if strcmp(status, 'won')
      totalScore = totalScore + 200 * level;% bonus for the completed level
      if level < nLevels
        show_screen(ax, {'LEVEL COMPLETE!', '', sprintf('Score: %d', totalScore), ...
                         '', sprintf('Get ready for level %d...', level + 1)});
        pause(2);
      endif
      level = level + 1;                    % next level (harder)
    endif
  endwhile

  if ~ishandle(fig)
    break;
  endif

  % ---- End of the game ------------------------------------------------------
  if lives > 0 && level > nLevels
    outcome = 'WIN - all levels completed!';
  else
    outcome = 'GAME OVER';
  endif
  if totalScore > bestScore
    bestScore = totalScore;                 % new record
  endif

  fid = fopen('results.txt', 'a');          % save the result (append mode)
  fprintf(fid, '%s ; level %d ; score %d ; lives %d ; %s\n', ...
          datestr(now, 'yyyy-mm-dd HH:MM:SS'), min(level, nLevels), totalScore, lives, outcome);
  fclose(fid);

  show_screen(ax, {outcome, '', sprintf('Score: %d   Best score: %d', totalScore, bestScore), ...
                   '', 'Answer in the command window'});
  keepPlaying = ask_replay();               % replay or stop
endwhile

disp('Thanks for playing!');      segLen = 40 - 3 * level + 10 * rand();% ground pieces get shorter
    endif
    segStarts(s) = x;
    S(end+1, :) = [x, -10, x + segLen, 0];  % ground piece
    hasBlock = false;
    if level >= 2 && s > 1 && rand() < 0.5
      bx = x + segLen * (0.35 + 0.3 * rand());
      bh = 3 + 2 * rand() + (level >= 4) * 2;
      S(end+1, :) = [bx, 0, bx + 5, bh];    % block to jump over
      hasBlock = true;
    endif
    if s > 1 && ~hasBlock && rand() < 0.35 + 0.1 * level
      enemies(end+1, :) = [x + 4, x + segLen - 4, 0.15 + 0.07 * level];  % faster enemies
    endif
    coinY = 5 + 4 * hasBlock;               % coins above blocks are higher
    coins(end+1:end+3, :) = [x + segLen * [0.25; 0.5; 0.75], [coinY; coinY; coinY]];
    if s < nSeg
      gap = 6 + 3.2 * level + 2 * rand();   % holes get wider
      gx  = x + segLen;
      if level <= 2 && rand() < 0.5
        S(end+1, :) = [gx + gap/2 - 3, 5, gx + gap/2 + 3, 6.5];  % stepping stone (easy levels)
      endif
      coins(end+1:end+3, :) = [gx + gap * [0.25; 0.5; 0.75], [11; 12; 11]];
      x = gx + gap;
    else
      x = x + segLen;
    endif
  endfor
  goalX       = x - 8;                      % flag position
  worldLength = x + 5;
endfunction

% ---- Function: a key is pressed ----------------------------------------
function key_press(fig, evt)
  keys = getappdata(fig, 'keys');           % [left right] pressed state
  switch evt.Key
    case 'left'
      keys(1) = true;
    case 'right'
      keys(2) = true;
    case {'up', 'space'}
      setappdata(fig, 'jumpRequested', true);  % jump asked
  endswitch
  setappdata(fig, 'keys', keys);
endfunction

% ---- Function: a key is released ---------------------------------------
function key_release(fig, evt)
  keys = getappdata(fig, 'keys');
  switch evt.Key
    case 'left'
      keys(1) = false;
    case 'right'
      keys(2) = false;
  endswitch
  setappdata(fig, 'keys', keys);
endfunction

% ---- Function: display a text screen (rules, results) ------------------
function show_screen(ax, message)
  set(get(ax, 'Parent'), 'Color', [0.05 0.05 0.2]);  % dark background
  cla(ax);
  axis(ax, [0 100 0 100]);
  axis(ax, 'off');
  text(ax, 50, 50, message, 'HorizontalAlignment', 'center', ...
       'Color', 'w', 'FontSize', 14);
  drawnow();
endfunction

% ---- Function: ask the player to replay --------------------------------
function answer = ask_replay()
  choice = input('Play again? (y/n): ', 's');
  answer = strcmpi(choice, 'y');
endfunction

% ---- Clean workspace ----------------------------------------------------
clear; clc; close all;

% ---- Parameters ---------------------------------------------------------
nLevels     = 5;       % number of levels
startLives  = 5;       % lives for the whole
playerW     = 3;       % player width
playerH     = 4;       % player height
enemyW      = 3;       % enemy width
enemyH      = 3;       % enemy height
enemyY      = 0;       % enemies walk on the ground
gravity     = 0.1;     % gravity (units per frame)
jumpSpeed   = 1.6;     % initial speed of a jump
maxSpeed    = 0.8;     % running speed (lower = slower)
framePause  = 0.025;   % pause between frames (s), increase it if the game is too fast
skyColors   = [0.45 0.75 1.00; 0.55 0.85 0.65; 0.95 0.70 0.45; 0.55 0.35 0.65; 0.10 0.10 0.25];
bestScore   = 0;       % best score over all games
keepPlaying = true;    % replay flag

% ---- Brain shape (relative to the player position) ----------------------
angle  = linspace(0, 2*pi, 120);                           % angles around the brain
bumps  = 1 + 0.07 * sin(9 * angle);                        % small bumps = brain folds
brainX = 0.46 * playerW * bumps .* cos(angle);             % outline x (relative to px)
brainY = 0.46 * playerH * bumps .* sin(angle) + playerH/2; % outline y (relative to py)
foldT  = linspace(0, 1, 30);                               % parameter of the central fold
foldX  = 0.10 * playerW * sin(4 * pi * foldT);             % wavy line x
foldY  = playerH * (0.12 + 0.76 * foldT);                  % wavy line y

% ---- Figure (resizable) and keyboard callbacks --------------------------
fig = figure('Name', 'Super Octave', 'NumberTitle', 'off');
ax  = axes('Parent', fig, 'Position', [0 0 1 1]);
setappdata(fig, 'keys', [false false]);     % [left right] pressed state
setappdata(fig, 'jumpRequested', false);
set(fig, 'KeyPressFcn',   @(src, evt) key_press(src, evt));    % key pressed
set(fig, 'KeyReleaseFcn', @(src, evt) key_release(src, evt));  % key released

while keepPlaying && ishandle(fig)

  % ---- New game: reset everything ---------------------------------------
  runSeed    = randi(1000);                 % new seed = new levels at each replay
  level      = 1;
  lives      = startLives;
  totalScore = 0;

  show_screen(ax, {'SUPER OCTAVE', '', ...
    'Use the LEFT / RIGHT arrows to run.', ...
    'Press the UP arrow (or SPACE) to jump.', ...
    'Jump on enemies to kill them (+100), collect coins (+10).', ...
    'Falling in a hole or touching an enemy = -1 life.', ...
    sprintf('Reach the flag in each of the %d levels with %d lives.', nLevels, startLives), ...
    '', 'Press any key to start'});
  waitforbuttonpress();

  while level <= nLevels && lives > 0 && ishandle(fig)

    % ---- Build the level ------------------------------------------------
    [S, coins, enemies, segStarts, goalX, worldLength] = build_level(level, runSeed);
    nCoins    = size(coins, 1);
    nEnemies  = size(enemies, 1);
    coinAlive = true(1, nCoins);
    enMin     = enemies(:, 1)';
    enMax     = enemies(:, 2)';
    enSpeed   = enemies(:, 3)';
    enX       = enMin + rand(1, nEnemies) .* (enMax - enMin);  % random start position
    enDir     = ones(1, nEnemies);          % walking direction (+1 / -1)
    enAlive   = true(1, nEnemies);

    show_screen(ax, {sprintf('LEVEL %d / %d', level, nLevels), '', 'Get ready...'});
    pause(1.5);

    % ---- Draw the level (pseudo-3D: shadow behind each block) -------------
    set(fig, 'Color', skyColors(level, :));
    cla(ax); axis(ax, [0 100 -12 48]); axis(ax, 'off'); hold(ax, 'on');
    for k = 1:size(S, 1)
      w = S(k,3) - S(k,1);
      h = S(k,4) - S(k,2);
      rectangle('Parent', ax, 'Position', [S(k,1) + 1.2, S(k,2) - 1.2, w, h], ...
                'FaceColor', [0.15 0.1 0.05], 'EdgeColor', 'none');   % shadow = depth effect
      if S(k,2) == -10
        rectangle('Parent', ax, 'Position', [S(k,1), S(k,2), w, h], ...
                  'FaceColor', [0.55 0.35 0.15], 'EdgeColor', 'k');   % ground
        rectangle('Parent', ax, 'Position', [S(k,1), -0.8, w, 0.8], ...
                  'FaceColor', [0.2 0.7 0.2], 'EdgeColor', 'none');   % grass
      else
        rectangle('Parent', ax, 'Position', [S(k,1), S(k,2), w, h], ...
                  'FaceColor', [0.6 0.6 0.65], 'EdgeColor', 'k');     % block / stone
      endif
    endfor
    rectangle('Parent', ax, 'Position', [goalX, 0, 0.8, 14], 'FaceColor', [0.9 0.9 0.9]);  % flag pole
    patch('Parent', ax, 'XData', [goalX + 0.8, goalX + 7, goalX + 0.8], ...
          'YData', [14, 11.5, 9], 'FaceColor', [1 0.1 0.1]);                              % flag
    hCoin = zeros(1, nCoins);
    for k = 1:nCoins
      hCoin(k) = rectangle('Parent', ax, 'Position', [coins(k,1) - 1, coins(k,2) - 1, 2, 2], ...
                           'Curvature', [1 1], 'FaceColor', [1 0.85 0], 'EdgeColor', 'k');
    endfor
    hEn = zeros(1, nEnemies);
    for k = 1:nEnemies
      hEn(k) = rectangle('Parent', ax, 'Position', [enX(k) - enemyW/2, enemyY, enemyW, enemyH], ...
                         'Curvature', [0.4 0.4], 'FaceColor', [0.6 0.2 0.1], 'EdgeColor', 'k');
    endfor
    hPlayer = patch('Parent', ax, 'XData', 5 + brainX, 'YData', brainY, ...
                    'FaceColor', [1 0.65 0.75], 'EdgeColor', [0.6 0.1 0.3], ...
                    'LineWidth', 1.5);                   % pink brain body
    hFold   = line('Parent', ax, 'XData', 5 + foldX, 'YData', foldY, ...
                   'Color', [0.6 0.1 0.3], 'LineWidth', 1.5);  % central fold line
    hInfo = text(ax, 2, 46, '', 'Color', 'w', 'FontSize', 12, ...
                 'BackgroundColor', [0.1 0.1 0.1], 'VerticalAlignment', 'top');

    % ---- Reset the player for this level ------------------------------------
    px = 5; py = 0; vy = 0;                 % position and vertical speed
    onGround = false;
    invuln   = 0;                           % invulnerability frames after a hit
    camX     = 0;                           % camera position
    status   = 'playing';
    setappdata(fig, 'jumpRequested', false);
    setappdata(fig, 'keys', [false false]); % avoid a key stuck from the previous level

    % ---- Main loop of one level ---------------------------------------------
    while strcmp(status, 'playing') && ishandle(fig)
      died = false;

      % Input: run with the left/right arrows
      keys = getappdata(fig, 'keys');       % [left right]
      vx   = maxSpeed * (keys(2) - keys(1));% +speed right, -speed left, 0 if none or both

      % Input: jump (only if standing on something)
      if getappdata(fig, 'jumpRequested')
        if onGround
          vy = jumpSpeed;
          onGround = false;
        endif
        setappdata(fig, 'jumpRequested', false);
      endif

      % Horizontal movement and collisions with solids
      pxNew = px + vx;
      hitX  = find(pxNew + playerW/2 > S(:,1) & pxNew - playerW/2 < S(:,3) & ...
                   py + playerH > S(:,2) & py < S(:,4) - 1e-6);
      for k = hitX(:)'
        if vx > 0
          pxNew = S(k,1) - playerW/2;       % stopped by the left side of the solid
        elseif vx < 0
          pxNew = S(k,3) + playerW/2;       % stopped by the right side of the solid
        endif
      endfor
      px = max(pxNew, playerW/2);           % left wall of the world

      % Vertical movement (gravity) and collisions with solids
      vy    = vy - gravity;
      pyNew = py + vy;
      onGround = false;
      if vy < 0
        land = find(px + playerW/2 > S(:,1) & px - playerW/2 < S(:,3) & ...
                    py >= S(:,4) - 1e-6 & pyNew < S(:,4));
        if ~isempty(land)
          pyNew = max(S(land, 4));          % land on the highest solid
          onGround = true;
          vy = 0;
        endif
      elseif vy > 0
        bump = find(px + playerW/2 > S(:,1) & px - playerW/2 < S(:,3) & ...
                    py + playerH <= S(:,2) + 1e-6 & pyNew + playerH > S(:,2));
        if ~isempty(bump)
          pyNew = min(S(bump, 2)) - playerH;% head hits a solid
          vy = 0;
        endif
      endif
      py = pyNew;

      % Enemies: walk back and forth
      enX  = enX + enDir .* enSpeed;
      turn = enX > enMax | enX < enMin;
      enDir(turn) = -enDir(turn);
      enX  = min(max(enX, enMin), enMax);

      % Enemies: collision with the player
      if invuln > 0
        invuln = invuln - 1;
      endif
      hitE = find(enAlive & abs(px - enX) < (playerW + enemyW)/2 & ...
                  py < enemyY + enemyH & py + playerH > enemyY);
      for k = hitE(:)'
        if vy < 0 && py > enemyY + enemyH * 0.4
          enAlive(k) = false;               % stomp: enemy killed
          vy = 0.6 * jumpSpeed;             % small bounce
          totalScore = totalScore + 100;
        elseif invuln == 0
          died = true;                      % touched from the side
        endif
      endfor

      % Coins
      coinHit = find(coinAlive & abs(coins(:,1)' - px) < 3 & abs(coins(:,2)' - (py + playerH/2)) < 4);
      for k = coinHit(:)'
        coinAlive(k) = false;
        set(hCoin(k), 'Visible', 'off');
        totalScore = totalScore + 10;
      endfor

      % Falling in a hole
      if py < -25
        died = true;
      endif

      % Death: lose a life and go back to the last checkpoint
      if died
        lives = lives - 1;
        if lives == 0
          status = 'lost';
        else
          px = max(segStarts(segStarts <= px)) + 2;   % start of the last ground piece
          py = 0; vy = 0;
          invuln = 60;
        endif
      endif

      % Flag reached
      if px >= goalX
        status = 'won';
      endif

      % Camera and graphics
      camX = min(max(px - 30, 0), worldLength - 100);
      set(ax, 'XLim', [camX camX + 100]);
      set(hPlayer, 'XData', px + brainX, 'YData', py + brainY);  % move the brain
      set(hFold,   'XData', px + foldX,  'YData', py + foldY);   % move the fold line
      if invuln > 0 && mod(floor(invuln / 5), 2) == 0
        set([hPlayer hFold], 'Visible', 'off');  % blinking when invulnerable
      else
        set([hPlayer hFold], 'Visible', 'on');
      endif
      for k = 1:nEnemies
        if enAlive(k)
          set(hEn(k), 'Position', [enX(k) - enemyW/2, enemyY, enemyW, enemyH]);
        else
          set(hEn(k), 'Visible', 'off');
        endif
      endfor
      set(hInfo, 'Position', [camX + 2, 46, 0], 'String', ...
          sprintf('Level %d/%d   Lives: %d   Score: %d', level, nLevels, lives, totalScore));
      drawnow();
      pause(framePause);
    endwhile

    if ~ishandle(fig)                       % figure closed by the player: stop
      break;
    endif

    % ---- End of the level ---------------------------------------------------
    if strcmp(status, 'won')
      totalScore = totalScore + 200 * level;% bonus for the completed level
      if level < nLevels
        show_screen(ax, {'LEVEL COMPLETE!', '', sprintf('Score: %d', totalScore), ...
                         '', sprintf('Get ready for level %d...', level + 1)});
        pause(2);
      endif
      level = level + 1;                    % next level (harder)
    endif
  endwhile

  if ~ishandle(fig)
    break;
  endif

  % ---- End of the game ------------------------------------------------------
  if lives > 0 && level > nLevels
    outcome = 'WIN - all levels completed!';
  else
    outcome = 'GAME OVER';
  endif
  if totalScore > bestScore
    bestScore = totalScore;                 % new record
  endif

  fid = fopen('results.txt', 'a');          % save the result (append mode)
  fprintf(fid, '%s ; level %d ; score %d ; lives %d ; %s\n', ...
          datestr(now, 'yyyy-mm-dd HH:MM:SS'), min(level, nLevels), totalScore, lives, outcome);
  fclose(fid);

  show_screen(ax, {outcome, '', sprintf('Score: %d   Best score: %d', totalScore, bestScore), ...
                   '', 'Answer in the command window'});
  keepPlaying = ask_replay();               % replay or stop
endwhile

disp('Thanks for playing!');

