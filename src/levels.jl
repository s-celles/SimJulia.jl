type Level
	name::ASCIIString
	capacity::Float64
	amount::Float64
	put_amounts::Dict{Process,Float64}
	get_amounts::Dict{Process,Float64}
	put_queue::PriorityQueue{Process,Int64}
	get_queue::PriorityQueue{Process,Int64}
	monitored::Bool
	put_monitor::Monitor{Int64}
	get_monitor::Monitor{Int64}
	buffer_monitor::Monitor{Float64}
	function Level(simulation::Simulation, name::ASCIIString, capacity::Float64, initial_buffered::Float64, monitored::Bool)
		level = new()
		level.name = name
		level.capacity = capacity
		level.amount = initial_buffered
		level.put_amounts = Dict{Process,Float64}()
		level.get_amounts = Dict{Process,Float64}()
		level.put_queue = PriorityQueue{Process,Int64}()
		level.get_queue = PriorityQueue{Process,Int64}()
		level.monitored = monitored
		if monitored
			level.put_monitor = Monitor{Int64}("Put monitor of $name")
			register(simulation, level.put_monitor)
			level.get_monitor = Monitor{Int64}("Get monitor of $name")
			register(simulation, level.get_monitor)
			level.buffer_monitor = Monitor("Buffer monitor of $name", initial_buffered)
			register(simulation, level.buffer_monitor)
		end
		return level
	end
end

function amount(level::Level)
	return level.amount
end

function acquired(process::Process, level::Level)
	result = true
	if has(level.put_amounts, process)
		delete!(level.put_queue, process)
		if level.monitored
			observe(level.put_monitor, now(process), length(level.put_queue))
		end
		delete!(level.put_amounts, process)
		result = false
	elseif has(level.get_amounts, process)
		delete!(level.get_queue, process)
		if level.monitored
			observe(level.get_monitor, now(process), length(level.get_queue))
		end
		delete!(level.get_amounts, process)
		result = false
	end
	return result
end

function put(process::Process, level::Level, give::Float64, priority::Int64, waittime::Float64, renege::Bool)
	if level.capacity - level.amount < give || length(level.put_queue) > 0
		level.put_amounts[process] = give
		push!(level.put_queue, process, priority)
		if level.monitored
			observe(level.put_monitor, now(process), length(level.put_queue))
		end
		if renege
			post(process.simulation, process, now(process)+waittime, true)
		end
	else
		level.amount += give
		if level.monitored
			observe(level.buffer_monitor, now(process), level.amount)
		end
		post(process.simulation, process, now(process), true)
		while length(level.get_queue) > 0
			new_process, new_priority = shift!(level.get_queue)
			ask = level.get_amounts[new_process]
			if level.amount >= ask
				level.amount -= ask
				if level.monitored
					observe(level.buffer_monitor, now(new_process), level.amount)
					observe(level.get_monitor, now(new_process), length(level.get_queue))
				end
				delete!(level.get_amounts, new_process)
				post(new_process.simulation, new_process, now(new_process), true)
			else
				break
			end
		end
	end
	produce(true)
end

function put(process::Process, level::Level, give::Float64, priority::Int64, waittime::Float64)
	put(process, level, give, priority, waittime, true)
end

function put(process::Process, level::Level, give::Float64, priority::Int64)
	put(process, level, give, priority, Inf, false)
end
	
function put(process::Process, level::Level, give::Float64, waittime::Float64)
	put(process, level, give, 0, waittime, true)
end

function put(process::Process, level::Level, give::Float64)
	put(process, level, give, 0, Inf, false)
end

function get(process::Process, level::Level, ask::Float64, priority::Int64, waittime::Float64, renege::Bool)
	if level.amount < ask || length(level.get_queue) > 0 
		level.get_amounts[process] = ask
		push!(level.get_queue, process, priority)
		if level.monitored
			observe(level.get_monitor, now(process), length(level.get_queue))
		end
		if renege
			post(process.simulation, process, now(process)+waittime, true)
		end
	else
		level.amount -= ask
		if level.monitored
			observe(level.buffer_monitor, now(process), level.amount)
		end
		post(process.simulation, process, now(process), true)
		while length(level.put_queue) >0
			new_process, new_priority = shift!(level.put_queue)
			give = level.put_amounts(new_process)
			if level.capacity - level.amount >= give
				level.amount += give
				if level.monitored
					observe(level.buffer_monitor, now(new_process), level.amount)
					observe(level.put_monitor, now(new_process), length(level.put_queue))
				end
				delete!(level.put_amounts, new_process)
				post(new_process.simulation, new_process, now(new_process), true)
			else
				break
			end
		end
	end
	produce(true)
end

function get(process::Process, level::Level, ask::Float64, priority::Int64, waittime::Float64)
	get(process, level, ask, priority, waittime, true)
end

function get(process::Process, level::Level, ask::Float64, priority::Int64)
	get(process, level, ask, priority, Inf, false)
end

function get(process::Process, level::Level, ask::Float64, waittime::Float64)
	get(process, level, ask, 0, waittime, true)
end

function get(process::Process, level::Level, ask::Float64)
	get(process, level, ask, 0, Inf, false)
end

function put_monitor(level::Level)
	return level.put_monitor
end

function get_monitor(level::Level)
	return level.get_monitor
end

function buffer_monitor(level::Level)
	return level.buffer_monitor
end
