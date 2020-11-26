% This file is the project entry point

clc;
clear;
close all;

% Parameters
SHOW_DEBUG = false;
HOUGH_RHO_RES = 1;
HOUGH_THETA_RES = 0.2;


in_file = 'classroom.png';
out_file = 'classroom_scan.png';

img = imread(in_file);

% Convert to greyscale
img_bw = uint8(rgb2gray(img));
[img_bin, thres] = binaryImage2(img_bw);

if (SHOW_DEBUG)
    figure;
    montage({img_bw, img_bin},'Size',[1 2]);
end


%% Apply edge detection filter (note: sobel is not suitable because lines could be diagonal)
img_grad = edge_grad(img_bin, thres);

%% Hough transform
[H, T, R] = hough(img_grad,'RhoResolution', HOUGH_RHO_RES ,'Theta', -90:HOUGH_THETA_RES:89);

% Make bright spots more visible
H = H .^ 2;

%% Find points from H (binary search) (0.7 seconds vs 1.75s of old method)
peaks = hough_search(H, 4, 10);
lines = houghlines(img_bw, T, R, peaks);

line_verts = hough_lines2verts(lines);
points = intersection_points(line_verts, img);
draw_detection(img, line_verts, points);

%%
% Control (original image)
h = size(img, 1);
w = 4/3 * h;
% w = 16/9 * h;
C = [0, 0;
     w, 0;
     0, h;
     w, h];

tf = fitgeotrans(points, C, 'projective');
[img_rectified, ref] = imwarp(img, tf);

% tf2 = affine2d([1 0 0; 0 1 0; 20 30 1]);

wx = ref.XWorldLimits(1);
wy = ref.YWorldLimits(1);

% img_rectified = imwarp(img, 
if (SHOW_DEBUG)
    figure;
    imshow(img_rectified);
    hold on
end

% Control points on the new graph
new_points = [];
for i = 1:size(points, 1)
    x_i = points(i, 1);
    y_i = points(i, 2);
    
    [x_o, y_o] = tf.transformPointsForward(x_i, y_i);
    
    xx = round(x_o - wx);
    yy = round(y_o - wy);
    
    new_points = [new_points; xx, yy];

    if (SHOW_DEBUG)
        plot(xx, yy, 'g*', 'MarkerSize', 10)
    end
end

if (SHOW_DEBUG)
    hold off
end

%% don't care about anything else lol

minnp = min(new_points);
maxnp = max(new_points);

% img_bl(1:minnp(2),:,:) = 0;
% img_bl(maxnp(2):ref.ImageSize(1),:,:) = 0;

img_cropped = imcrop(img_rectified, [minnp, maxnp - minnp]);
    img_cropped_grey = rgb2gray(img_cropped);

if (SHOW_DEBUG)
    figure;
    imshowpair(img_cropped, img_cropped_grey, 'montage');
end

%% Document segmentation (TODO: use the rice example from HW4)
img_doc = imadjust(img_cropped_grey);
img_doc = imbinarize(img_doc, 'adaptive', 'Sensitivity', 0.630000, 'ForegroundPolarity', 'bright');
figure;
imshow(img_doc);

%% Save the image
imwrite(img_doc, outfile);

%% Functions

function img = edge_sobel(I, thres)
    gx = [-1 -2 -1; 0 0 0; 1 2 1];
    gy = [-1 0 1; -2 0 2; -1 0 1];
    img_gx = conv2(I, gx);
    img_gy = conv2(I, gy);
    img = abs(img_gx) + abs(img_gy);
    img(img < thres) = 0;
end

function img = edge_grad(I, thres)
    img = imgradient(I);
    img(img < thres) = 0;
end

function points = hough_search(H, n, max_epoch)
    ratio_hi = 1.0;
    ratio_lo = 0.0;
    epoch = 0;

    while epoch < max_epoch
        ratio = (ratio_hi - ratio_lo) / 2 + ratio_lo;

        mask = H > ratio * max(H(:));
        mask = bwmorph(mask, 'dilate', 15);
        mask = bwmorph(mask, 'shrink', Inf);
        mask = double(mask);

        [r_idx, t_idx] = find(mask);
        points = [r_idx, t_idx];

        if size(points, 1) > n
            ratio_hi = ratio;
        elseif size(points, 1) < n
            ratio_lo = ratio;
        else
            break
        end
        
        epoch = epoch + 1;
    end
end

% This function finds the lines in spatial/px coordinates from hough lines
function line_verts = hough_lines2verts(lines)
    line_verts = zeros(4, 2, 2);

    for k = 1:numel(lines)
        x1 = lines(k).point1(1);
        y1 = lines(k).point1(2);
        x2 = lines(k).point2(1);
        y2 = lines(k).point2(2);
        
        line_verts(k,1,:) = [x1 x2];
        line_verts(k,2,:) = [y1 y2];
    end
end

function points = intersection_points(line_verts, img)
    points = [];
    index_opts = nchoosek(1:4, 2);
    for i = 1:size(index_opts, 1)
        l1_idx = index_opts(i, 1);
        l2_idx = index_opts(i, 2);
        
        x1 = line_verts(l1_idx,1,:);
        y1 = line_verts(l1_idx,2,:);
        x2 = line_verts(l2_idx,1,:);
        y2 = line_verts(l2_idx,2,:);
        
        [x_i, y_i] = intersection(x1, y1, x2, y2);
        
        % discard points outside of image
        if x_i < 0 || x_i > size(img, 2) || y_i < 0 || y_i > size(img, 1)
            continue
        end

        points = [points; x_i y_i];
    end
end

% https://www.mathworks.com/matlabcentral/answers/70287-to-find-intersection-point-of-two-lines
function [x, y] = intersection(x1, y1, x2, y2)
    p1 = polyfit(x1, y1, 1);
    p2 = polyfit(x2, y2, 1);
    x = fzero(@(x) polyval(p1 - p2, x), 3);
    y = polyval(p1, x);
end

% Draw picture with detected lines and intersection points
function draw_detection(img, line_verts, points)
    figure;
    imshow(img);

    hold on
    for k = 1:size(line_verts, 1)
        x1 = line_verts(k, 1, 1);
        x2 = line_verts(k, 1, 2);
        y1 = line_verts(k, 2, 1);
        y2 = line_verts(k, 2, 2);
        plot([x1 x2],[y1 y2],'Color','g','LineWidth', 2);
    end

    for k = 1:size(points, 1)
        plot(points(k, 1), points(k, 2), 'r*');
    end
    hold off
end