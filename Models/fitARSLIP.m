%This set of functions fit ARSLIP model to a experimental data by
%optimization.
%Initial guesses of initial conditions are taken from experimental data.
%
%@Chanwoo Chun, <cc2465@cornell.edu>

function data_output = fitARSLIP(data,st)

%convert yexp (mm) to (cm) by dividing by a factor of 10. This change is not going to be saved.
data.com = data.com;
data.vel3D = data.vel3D;

%Comment out below two lines of code to enable fitting to a pure tripod
%stance phases. Uncomment if you want to fit to entire tripod stance phase.
data.pureTriStarts = 1;
data.pureTriEnds = size(data.com,1);

% Construct fixed structure
fixed.g      = 9807; %mm/s^2
fixed.M      = data.source.weight/1000; %gram
expLegLength = data.source.legLength;

%Definitions and units.
%gammaA = ka/(mgR)
%Ka unit  = kg(m/s)^2 = N*m*rad^-1 = 10^3gram*(10^3mm/s)^2 = 10^9gram*(mm/s)^2
% kg(m/s)^2 / 10^9 gram(mm/s)^2 = 1
%gammaA unit = gram(mm/s)^2/(gram * mm/s^2 *mm) = 1
%Omega unit = rad/s 

%Set up unconstrained minimization
objective = @(X) objectiveFunc(X, data, fixed, st);

A = []; b = []; % no linear inequality constraints
Aeq = []; beq = []; % no linear equality constraints


AP = median(data.com(:,1));% Initial anchor point
travelLength = data.com(end,1)-data.com(1,1);
APlb = data.com(1,1)-travelLength/3;%define lower bound
APub = data.com(end,1)+travelLength/3;%define upper bound

%take initial conditions for position from exp. data
xzPosInit = data.com(data.pureTriStarts,:);
xzVelInit = data.vel3D(data.pureTriStarts,:); 

%calculate initial condition for leg length and speed (omega and dRdt0)
%from experimental data
R0 = sqrt(xzPosInit(2)^2+(AP-xzPosInit(1))^2);
%Calculate dRdt0 and omega
A = -AP+xzPosInit(1);
B = xzPosInit(2);
legUnitVector = [A, B]/norm([A, B]);
dRdt0 = sum(legUnitVector.*xzVelInit); %dot product
tanVel0 = xzVelInit-dRdt0*legUnitVector;
tanSpeed0 = sqrt(tanVel0(1)^2+tanVel0(2)^2);
omega = tanSpeed0/R0;

%Initial guess of the parameter values
params0 = [expLegLength; R0; 13; 25; AP; dRdt0; omega]; %Rnat R0 Ka Ks AP dRdt0 omega
lb = [expLegLength*0.95; R0*0.25; 0;  0; APlb; dRdt0-2*dRdt0; omega*0.25]; % lower bound for parameters
ub = [expLegLength*1.05; R0*3; 50; 50; APub; dRdt0+2*dRdt0; omega*3]; % upper bound for parameters 

lbTemp = min([lb ub],[],2);
ubTemp = max([lb ub],[],2);
lb = lbTemp;
ub = ubTemp;
% Option 1:
%options = optimoptions('fmincon','Algorithm','sqp','Display','iter','GradObj','off','MaxIterations',1500,'MaxFunctionEvaluations',3000);
% Option 2:
options = optimoptions('fmincon','Algorithm','interior-point','Display','iter', ...
     'GradObj','off');
problem = createOptimProblem('fmincon','x0',params0,'objective',objective,...
    'lb',lb,'ub',ub,'options',options);

gs = GlobalSearch('NumTrialPoints', 2000); %15000 %2000

%try
    [reconstructed, f] = run(gs, problem);
% catch
%     %If ran in to an error during optimization, save NaN to the parameters.
%     data_output=data;
%     return
% end

%Assign optimized parameter values.
Rnat    = reconstructed(1);
R0      = reconstructed(2);
Ka      = reconstructed(3);
Ks      = reconstructed(4);
AP      = reconstructed(5);
dRdt0   = reconstructed(6);
omega   = reconstructed(7);
APpct = reconstructed(5)/travelLength*100;

%Solve ODE to save optimized solutions.
thetasim_interp = getCoordinates(reconstructed, data, fixed, st);
R = thetasim_interp(:,3);
% Compute predicted trajectory in x and z directions
ysim(:,1) = R.*(sin(thetasim_interp(:,1))-sin(thetasim_interp(1,1)))+data.com(data.pureTriStarts(1),1);
ysim(:,2) = R.*(cos(thetasim_interp(:,1)));
% Raw solution (angle, angular speed, leg length, and leg speed)
rawSolution = thetasim_interp;

data.ARSLIP.Rnat = Rnat;
data.ARSLIP.R0 = R0;
data.ARSLIP.Ka = Ka;
data.ARSLIP.Ks = Ks;
data.ARSLIP.AP = AP;
data.ARSLIP.APpct = APpct;
data.ARSLIP.dRdt0 = dRdt0;
data.ARSLIP.omega = omega;
data.ARSLIP.f = f;
data.ARSLIP.ysim = ysim;
data.ARSLIP.rawSolution = rawSolution;
data.ARSLIP.movesBack = false;
if any(ysim(:,2)<=0)
        data.ARSLIP.movesBack = true;
end
data_output=data;

end

%%

function [ f, g ] = objectiveFunc( params, data, fixed, st)
%Compute the score and its derivative WRT the parameters
%   params: [Rnat R0 Ka Ks AP dRdt0 omega]
%   yexp: an Ntx2 vector of data in x and z directions
%   fixed: a structure of fixed quantities
pureTriStarts = data.pureTriStarts(1);
pureTriEnds = data.pureTriEnds(1);

% Load data
yexp = data.com;

% Compute the score of current params
% First, solve for theta and R using ODE
thetasim_interp = getCoordinates(params, data, fixed, st);
R = thetasim_interp(:,3);
% Compute predicted trajectory in x and z directions
ysim(:,1) = R.*(sin(thetasim_interp(:,1))-sin(thetasim_interp(1,1)))+yexp(pureTriStarts,1);
ysim(:,2) = R.*(cos(thetasim_interp(:,1)));

% Compare predictions to data for the score ONLY FOR PURE TRIPOD
RMSE=sqrt(mean((ysim-yexp(pureTriStarts:pureTriEnds,:)).^2,1));
f=sum(RMSE);

if nargout > 1
    % Compute the derivative of the objective
end

end

%%
function thetasim_interp = getCoordinates(params, data, fixed, st)
time  = data.time;
pureTriStarts = data.pureTriStarts(1);
pureTriEnds = data.pureTriEnds(1);

% Current parameters
Rnat    = params(1);
R0      = params(2);
Ka      = params(3);
Ks      = params(4);
AP      = params(5);
dRdt0   = params(6);
omega   = params(7);

% Calculate alpha
xzPosInit = data.com(pureTriStarts,:);
alpha = -asin((AP-xzPosInit(1))/R0);

% Fixed quantities
g = fixed.g;
M = fixed.M;
% Specify the ODE
ode = @(t,y) govEqu(t, y, g, M, Rnat, Ka, Ks);
% Solve ODE over time interval
[tsim,thetasim] = ode45(ode,[time(pureTriStarts) time(pureTriEnds)],[alpha omega R0 dRdt0]); % first square bracket is the time range, second is initial condition
% Interpolate the simulated solution to predicted values at time points

thetasim_interp(:,1) = interp1(tsim,thetasim(:,1),time(pureTriStarts:pureTriEnds)); %For angle
thetasim_interp(:,2) = interp1(tsim,thetasim(:,2),time(pureTriStarts:pureTriEnds)); %For anglure velocity
thetasim_interp(:,3) = interp1(tsim,thetasim(:,3),time(pureTriStarts:pureTriEnds)); %For leg length
thetasim_interp(:,4) = interp1(tsim,thetasim(:,4),time(pureTriStarts:pureTriEnds)); %For leg length change speed
end

%%
function dydt = govEqu(t, y, g, M, R, Ka, Ks)
%For ARSLIP
%y(1) = angle, y(2) = anglur speed, y(3) = r, y(4) = r'
dydt =[y(2);
      g*sin(y(1))/y(3) - y(1)*(Ka/M)/(y(3)*y(3)) - 2*y(2)*y(4)/y(3);
      y(4);
      -g*cos(y(1))+ y(3)*y(2)*y(2) - (Ks/M)*(y(3)-R)];
end