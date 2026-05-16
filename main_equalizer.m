clc
clear
close all

%% =========================
% Multi-Band Speech Equalizer
%% =========================

% Audio file
file_name = 'Albumaty.Com_amrw_dyab_khtfwny.wav';

% Read audio
[x, Fs] = audioread(file_name);

% Convert stereo to mono
if size(x,2) == 2
    x = mean(x,2);
end

%% =========================
% User Inputs
%% =========================

mode_choice = 1;
% 1 = preset
% 2 = custom

filter_main = 1;
% 1 = FIR
% 2 = IIR

filter_order = 50;

output_fs = Fs;

%% =========================
% FIR Window Choice
%% =========================

window_choice = 1;

% 1 = Hamming
% 2 = Hanning
% 3 = Blackman

%% =========================
% IIR Filter Choice
%% =========================

iir_choice = 1;

% 1 = Butterworth
% 2 = Chebyshev Type I
% 3 = Chebyshev Type II

%% =========================
% Preset Bands
%% =========================

if mode_choice == 1

    bands = [
        0 100;
        100 300;
        300 800;
        800 2000;
        2000 5000;
        5000 10000;
        10000 20000
    ];

    gains_db = [
        -5;
        2;
        5;
        6;
        3;
        -2;
        -6
    ];

end

%% =========================
% Custom Bands
%% =========================

if mode_choice == 2

    bands = [
        0 200;
        200 500;
        500 1000;
        1000 3000;
        3000 6000;
        6000 10000;
        10000 20000
    ];

    gains_db = [
        3;
        5;
        2;
        -2;
        -3;
        -5;
        -7
    ];

end

%% =========================
% Initialize Output
%% =========================

y_total = zeros(size(x));

%% =========================
% Process Each Band
%% =========================

for i = 1:size(bands,1)

    f1 = bands(i,1);
    f2 = bands(i,2);

    gain_linear = 10^(gains_db(i)/20);

    %% =========================
    % FIR Filters
    %% =========================

    if filter_main == 1

        win = get_window(window_choice,filter_order+1);

        if f1 == 0

            wn = f2/(Fs/2);

            b = fir1(filter_order,wn,'low',win);

        elseif f2 >= Fs/2

            wn = f1/(Fs/2);

            b = fir1(filter_order,wn,'high',win);

        else

            wn = [f1 f2]/(Fs/2);

            b = fir1(filter_order,wn,'bandpass',win);

        end

        a = 1;

    end

    %% =========================
    % IIR Filters
    %% =========================

    if filter_main == 2

        if f1 == 0

            wn = f2/(Fs/2);

            if iir_choice == 1
                [b,a] = butter(4,wn,'low');

            elseif iir_choice == 2
                [b,a] = cheby1(4,1,wn,'low');

            else
                [b,a] = cheby2(4,40,wn,'low');
            end

        elseif f2 >= Fs/2

            wn = f1/(Fs/2);

            if iir_choice == 1
                [b,a] = butter(4,wn,'high');

            elseif iir_choice == 2
                [b,a] = cheby1(4,1,wn,'high');

            else
                [b,a] = cheby2(4,40,wn,'high');
            end

        else

            wn = [f1 f2]/(Fs/2);

            if iir_choice == 1
                [b,a] = butter(4,wn,'bandpass');

            elseif iir_choice == 2
                [b,a] = cheby1(4,1,wn,'bandpass');

            else
                [b,a] = cheby2(4,40,wn,'bandpass');
            end

        end

    end

    %% =========================
    % Display Filter Order
    %% =========================

    disp(['Band ' num2str(i)])
    disp(['Filter Order = ' num2str(length(b)-1)])

    %% =========================
    % Filter Analysis
    %% =========================

    figure('Name',['Band ' num2str(i) ' Filter Analysis'])

    subplot(3,2,1)
    freqz(b,a)
    title(['Magnitude & Phase Response - Band ' num2str(i)])

    subplot(3,2,2)
    impz(b,a)
    title('Impulse Response')

    subplot(3,2,3)
    stepz(b,a)
    title('Step Response')

    subplot(3,2,4)
    zplane(b,a)
    title('Pole-Zero Plot')

    subplot(3,2,5)
    stem(b)
    title('Numerator Coefficients')

    subplot(3,2,6)
    stem(a)
    title('Denominator Coefficients')

    %% =========================
    % Filter Signal
    %% =========================

    y_band = filter(b,a,x);

    %% =========================
    % Apply Gain
    %% =========================

    y_band = y_band * gain_linear;

    %% =========================
    % Combine Bands
    %% =========================

    y_total = y_total + y_band;

end

%% =========================
% Normalize Signal
%% =========================

y_total = 0.99 * y_total / max(abs(y_total));

%% =========================
% Output Sample Rate
%% =========================

y_total = resample(y_total,output_fs,Fs);

Fs = output_fs;

%% =========================
% Output Sample Rate Tests
%% =========================

y_up = resample(y_total,4,1);

y_down = resample(y_total,1,2);

%% =========================
% Time Domain Comparison
%% =========================

figure('Name','Time Domain Comparison')

subplot(2,1,1)
plot(x)
title('Original Signal')
xlabel('Samples')
ylabel('Amplitude')

subplot(2,1,2)
plot(y_total)
title('Equalized Signal')
xlabel('Samples')
ylabel('Amplitude')

%% =========================
% Frequency Domain Comparison
%% =========================

N = length(x);

X = fft(x);
Y = fft(y_total);

f = linspace(0,Fs,N);

figure('Name','Frequency Domain Comparison')

subplot(2,1,1)
plot(f,abs(X))
title('Original Spectrum')
xlabel('Frequency (Hz)')
ylabel('Magnitude')

subplot(2,1,2)
plot(f,abs(Y))
title('Equalized Spectrum')
xlabel('Frequency (Hz)')
ylabel('Magnitude')

%% =========================
% Power Spectral Density
%% =========================

figure('Name','Power Spectral Density')

subplot(2,1,1)
pwelch(x)
title('Original PSD')

subplot(2,1,2)
pwelch(y_total)
title('Equalized PSD')

%% =========================
% Spectrogram
%% =========================

figure('Name','Spectrogram Comparison')

subplot(2,1,1)
spectrogram(x,256,200,256,Fs,'yaxis')
title('Original Spectrogram')

subplot(2,1,2)
spectrogram(y_total,256,200,256,Fs,'yaxis')
title('Equalized Spectrogram')

%% =========================
% Play Audio
%% =========================

sound(y_total,Fs)

%% =========================
% Save Audio Files
%% =========================

audiowrite('equalized_output.wav',y_total,Fs);

audiowrite('equalized_x4.wav',y_up,Fs*4);

audiowrite('equalized_half.wav',y_down,Fs/2);

disp('Processing Complete')

%% =========================
% Window Function
%% =========================

function w = get_window(choice,N)

if choice == 1

    w = hamming(N);

elseif choice == 2

    w = hann(N);

else

    w = blackman(N);

end

end