classdef kinectcore < handle
    %kinectcore Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (SetAccess = protected)
        cam                 % selected kinect class
        CameraLocation      % Location of camera [x y z alfa beta gamma] (eul: ZYX absolute axes/ XYZ own axes)
        homeCameraLocation  % Home location of camera
        detectionVol        % Dimensions of volume where object are detected
        worktableVol        % Dimensions of worktable 
    end
    
    methods
        function obj = kinectcore(cam_selected)
            if cam_selected == 'vrep'
                obj.cam = kinectvrep();
            elseif cam_selected == 'real'
                obj.cam = kinectreal();
            end
            obj.homeCameraLocation = [0.67 1.68 1.09 90 0 0];
            obj.CameraLocation = zeros(1,6);
            obj.detectionVol = [-2 1.5 -2 1.6 0 2.3];
            obj.worktableVol = [-0.08 1.42 -0.7 0.7 0 2.32];
        end % constructor
        function set.CameraLocation(obj,Location)
            if length(Location)==6 && isnumeric(Location) ...
                    && sum(Location(4:6)>180)==0 && sum(Location(4:6)<-180)==0
                obj.CameraLocation = Location;
                if sum(Location(1:3)>10)>0 || sum(Location(1:3)<-10)>0
                    warning('Camera is placed more than 10m away from WCS.')
                end
            else
                error('Invalid CameraLocation!\n%s',...
                    'Values are outside range.')
            end
        end
        function set.detectionVol(obj,Vol)
            if length(Vol)==6 && isnumeric(Vol)
                obj.detectionVol =Vol;
            else
                error('Invalid detection volume!\n%s',...
                    'Values are invalid.')
            end
        end
        function set.worktableVol(obj,Vol)
            if length(Vol)==6 && isnumeric(Vol)
                obj.worktableVol =Vol;
            else
                error('Invalid worktable volume!\n%s',...
                    'Values are invalid.')
            end
        end
        
        function connect(obj)
            obj.cam.connectDif();
            obj.moveHome();
        end
        function disconnect (obj)
            obj.cam.Close();
        end
        function moveToCameraLocation(obj,Location)
            obj.CameraLocation = Location;
            obj.cam.moveToCameraLocationDif(Location);
        end
        function moveHome(obj)
            obj.moveToCameraLocation(obj.homeCameraLocation);
        end
        function [ptCloud] = desamplePointCloud(obj,ptCloud)
            [ptCloud,~] = removeInvalidPoints(ptCloud);
            ptCloud = pcdownsample(ptCloud,'gridAverage',0.1);
            if isa(obj.cam,'kinectvrep')
                ptCloud = obj.selectBox(ptCloud,[-inf inf -inf inf -inf 5],0.05); %remove clipping plane
            end
            ptCloud = obj.transformPointCloud(ptCloud);
            ptCloud = obj.selectBox(ptCloud,obj.detectionVol,0.1); % select detection area
        end
        function [ptCloud] = filterPointCloud(obj,ptCloud)
            if ~isempty(ptCloud.Location)
                ptCloud = pcdenoise(ptCloud,'Threshold',1);
            end
            ptCloud = obj.removeBox(ptCloud,obj.worktableVol,0.1); % remove worktable
        end
        function [ptCloud] = getRawPointCloud(obj)
            XYZ = obj.cam.GetFrame(TofFrameType.XYZ_3_COLUMNS);
            ptCloud = pointCloud(XYZ);
%             if isa(obj.cam,'kinectvrep')
%                 ptCloud = obj.selectBox(ptCloud,[-inf inf -inf inf -inf 5],0.05); %remove clipping plane
%             end
            ptCloud = obj.transformPointCloud(ptCloud);
        end
        function [ptCloud] = transformPointCloud(obj,ptCloud)
            RotMat = eul2rotm(obj.CameraLocation(4:6)./180.*pi,'XYZ');
            HomoTransMat = [ RotMat obj.CameraLocation(1:3).';...
                zeros(1,3) 1];
            XYZrow = ptCloud.Location.';
            XYZ = [XYZrow;ones(1,length(XYZrow))];
            Result = HomoTransMat*XYZ;
            ptCloud = pointCloud(Result(1:3,:).');
        end
        
        function [RGB] = getRGB(obj)
            RGB = obj.cam.GetFrame(TofFrameType.RGB_IMAGE);
        end
        function [ptCloud] = getDesampledPointCloud(obj)
            XYZ = obj.cam.GetFrame(TofFrameType.XYZ_3_COLUMNS);
            ptCloud = pointCloud(XYZ);
            ptCloud = obj.desamplePointCloud(ptCloud);
        end
        function [ptCloud] = getFilteredPointCloud(obj)
            [ptCloud] = obj.getDesampledPointCloud();
            [ptCloud] = obj.filterPointCloud(ptCloud);
        end
        function showPointCloud(obj,ptCloud)
            figure('Name','PointCloud');
            pcshow(ptCloud);
            axis equal
            title('PointCloud')
            xlabel('X [m]');
            ylabel('Y [m]');
            zlabel('Z [m]');
            hold on
            quiver3(0,0,0,1,0,0,0.3,'r','Linewidth',1.5)
            quiver3(0,0,0,0,1,0,0.3,'g','Linewidth',1.5)
            quiver3(0,0,0,0,0,1,0.3,'b','Linewidth',1.5)
            plotCamera('Location',obj.CameraLocation(1:3),'Orientation',eul2rotm(obj.CameraLocation(4:6)./180.*pi,'XYZ').','Opacity',0,'Size',0.1);
            hold off
        end
        function getPointCloudComparison(obj)
            ptCloudDesampled = obj.getDesampledPointCloud();
            ptCloudFiltered = obj.filterPointCloud(ptCloudDesampled);
            [dist,Point] = obj.getClosestPoint();
            
            figure('Name','PointCloud Comparison');
            s1=subplot(1,2,1);
            pcshow(ptCloudDesampled)
            axis equal
            %s1.CameraPosition = obj.CameraLocation(1:3);
            %s1.CameraTarget = [0 0 0];
            title('PointCloud Desampled')
            xlabel('X [m]');
            ylabel('Y [m]');
            zlabel('Z [m]');
            hold on
            quiver3(0,0,0,1,0,0,0.3,'r','Linewidth',1.5)
            quiver3(0,0,0,0,1,0,0.3,'g','Linewidth',1.5)
            quiver3(0,0,0,0,0,1,0.3,'b','Linewidth',1.5)
            plotCamera('Location',obj.CameraLocation(1:3),'Orientation',eul2rotm(obj.CameraLocation(4:6)./180.*pi,'XYZ').','Opacity',0,'Size',0.1);
            hold off
            
            s2=subplot(1,2,2);
            pcshow(ptCloudFiltered)
            axis equal
            s2.XLim = s1.XLim;
            s2.YLim = s1.YLim;
            s2.ZLim = s1.ZLim;
            s2.CameraPosition = s1.CameraPosition;
            s2.CameraTarget = s1.CameraTarget;
            title('PointCloud Filtered')
            xlabel('X [m]');
            ylabel('Y [m]');
            zlabel('Z [m]');
            hold on
            quiver3(0,0,0,1,0,0,0.3,'r','Linewidth',1.5)
            quiver3(0,0,0,0,1,0,0.3,'g','Linewidth',1.5)
            quiver3(0,0,0,0,0,1,0.3,'b','Linewidth',1.5)
            plotCamera('Location',obj.CameraLocation(1:3),'Orientation',eul2rotm(obj.CameraLocation(4:6)./180.*pi,'XYZ').','Opacity',0,'Size',0.1);
            obj.plotTable();
            if ~isinf(dist)
                plot3([0 Point(1)],[0 Point(2)],[0.988 Point(3)],'r')
                text(Point(1)/2,Point(2)/2,((Point(3)-0.988)/2)+0.988,[' ' num2str(round(dist,2)) ' m'])
            else
                text(0,0,1.3,'No point detected')
            end
            hold off
        end
        function getPointCloudCalibration(obj)
            ptCloud = obj.getRawPointCloud();
            figure('Name','PointCloud Calibration');
            s1 = pcshow(ptCloud);
            axis equal
            s1.CameraPosition = obj.CameraLocation(1:3);
            s1.CameraTarget = [0 0 0];
            title('PointCloud Calibration')
            xlabel('X [m]');
            ylabel('Y [m]');
            zlabel('Z [m]');
            hold on
            quiver3(0,0,0,1,0,0,0.3,'r','Linewidth',1.5)
            quiver3(0,0,0,0,1,0,0.3,'g','Linewidth',1.5)
            quiver3(0,0,0,0,0,1,0.3,'b','Linewidth',1.5)
            plotCamera('Location',obj.CameraLocation(1:3),'Orientation',eul2rotm(obj.CameraLocation(4:6)./180.*pi,'XYZ').','Opacity',0,'Size',0.1);
            obj.plotTable();
            hold off
        end
        function [Dist,Point] = getClosestPoint(obj)
            ptCloud = obj.getFilteredPointCloud();
            [indices, dists] = findNearestNeighbors(ptCloud,[0 0 0.988],1,'Sort',true);
            if ~isempty(indices)
                Dist = dists(1);
                Point = ptCloud.Location(indices,:);
            else
                Dist = inf;
                Point = [inf,inf,inf];
            end
        end
        function showPlayer(obj)
            player = pcplayer(obj.detectionVol(1:2),obj.detectionVol(3:4),obj.detectionVol(5:6));
            while isOpen(player)
               ptCloud = obj.getFilteredPointCloud();
               view(player, ptCloud);
            end
        end
        function showTrackingPlayer(obj)
            figure('Name','PointCloud Player');
            title('PointCloud Player')
            xlabel('X [m]');
            ylabel('Y [m]');
            zlabel('Z [m]');
            hold on
            quiver3(0,0,0,1,0,0,0.3,'r','Linewidth',1.5)
            quiver3(0,0,0,0,1,0,0.3,'g','Linewidth',1.5)
            quiver3(0,0,0,0,0,1,0.3,'b','Linewidth',1.5)
            plotCamera('Location',obj.CameraLocation(1:3),'Orientation',eul2rotm(obj.CameraLocation(4:6)./180.*pi,'XYZ').','Opacity',0,'Size',0.1);
            obj.plotTable();
            ptCloud = obj.getFilteredPointCloud();
            pcshow(ptCloud);
            axis([obj.detectionVol(1:2) obj.detectionVol(3:4) obj.detectionVol(5:6)])
            [dist,Point] = obj.getClosestPoint();
            if ~isinf(dist)
                plot3([0 Point(1)],[0 Point(2)],[0.988 Point(3)],'r')
                text(Point(1)/2,Point(2)/2,((Point(3)-0.988)/2)+0.988,[' ' num2str(round(dist,2)) ' m'])
            else
                plot3([0 0],[0 0],[0 0])
                text(0,0,1.3,'No point detected')
            end
            
            while true %add other control
                children = get(gca, 'children');
                delete(children(1));
                delete(children(2));
                delete(children(3));
                ptCloud = obj.getFilteredPointCloud();
                pcshow(ptCloud)
                axis([obj.detectionVol(1:2) obj.detectionVol(3:4) obj.detectionVol(5:6)])
                [dist,Point] = obj.getClosestPoint();
                if ~isinf(dist)
                    plot3([0 Point(1)],[0 Point(2)],[0.988 Point(3)],'r')
                    text(0,0,1.3,[' ' num2str(round(dist,2)) ' m'])
                else
                    plot3([0 0],[0 0],[0 0])
                    text(0,0,1.3,'No point detected')
                end
                drawnow 
            end
            
        end
        
    end
    
    methods (Static)
        function [ptCloud] = selectBox(ptCloud,dim,off)
            ROI = [dim(1)+off dim(2)-off dim(3)+off dim(4)-off dim(5)+off dim(6)-off];
            indices = findPointsInROI(ptCloud,ROI);
            [ptCloud] = select(ptCloud,indices);
        end
        function [ptCloud] = removeBox(ptCloud,dim,off)
            ROI = [dim(1)-off dim(2)+off dim(3)-off dim(4)+off dim(5)-off dim(6)+off];
            ind = findPointsInROI(ptCloud,ROI);
            indInv = setdiff((1:ptCloud.Count),ind);
            [ptCloud] = select(ptCloud,indInv);
            
        end
        function plotTable()
            % add robot base cylinder
            [x1,y1,z1] = cylinder(0.17/2,10);
            z1(1, :) = 0.845;
            z1(2, :) = 0.845+0.205;
            surf(x1,y1,z1,'FaceAlpha',0.3,'FaceColor','r')
            % add table top
            x2 = [-0.08 -0.08 -0.08 -0.08 -0.08;1.42 1.42 1.42 1.42 1.42];
            y2 = [-0.7 -0.7 0.7 0.7 -0.7; -0.7 -0.7 0.7 0.7 -0.7];
            z2 = [0.845 0.805 0.805 0.845 0.845; 0.845 0.805 0.805 0.845 0.845];
            surf(x2,y2,z2,'FaceAlpha',0.3,'FaceColor','r')
        end
        
    end
    
    
end

