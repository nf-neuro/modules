process SEGMENTATION_FSRECONALL {
    tag "$meta.id"
    label 'process_single'

    // Note. Freesurfer is already on Docker. See documentation on
    // https://hub.docker.com/r/freesurfer/freesurfer
    container "freesurfer/freesurfer:7.4.1"

    input:
        tuple val(meta), path(anat), path(fs_license) /* optional, input = [] */

    output:
        tuple val(meta), path("*__recon_all")   , emit: recon_all_out_folder
        path "versions.yml"                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    // Note. In dsl1, we used an additional option:   -parallel -openmp $params.nb_threads.
    // Removed here.
    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def dev_debug_test = task.ext.debug ? task.ext.debug : ""  // If true, we will only run the help (for unit tests )
    """
    export OMP_NUM_THREADS=${task.ext.single_thread ? 1 : task.cpus}

    # Manage the license. (Save old one if existed.)
    if [[ ! -f "$fs_license" ]]
    then
        echo "License not given in input, or not found. Will probably fail. "
    else
        cp "$fs_license" .license
        here=`pwd`
        export FS_LICENSE=\$here/.license
    fi

    if [ -z $dev_debug_test ]
    then
        # Run the main script
        export SUBJECTS_DIR=`pwd`
        recon-all -i $anat -s ${prefix}__recon_all -all
    else
        # (for developers: unit tests: skip the long processing. help only.)
        export SUBJECTS_DIR=`pwd`
        recon-all -i $anat -s ${prefix}__recon_all -autorecon1 -dontrun
    fi

    # Remove the license
    if [ ! $fs_license = [] ]; then
        rm .license
    fi


    # Finish
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9.]+).*/\\1/')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    set +e
    function handle_code () {
    local code=\$?
    ignore=( 1 )
    [[ " \${ignore[@]} " =~ " \$code " ]] || exit \$code
    }
    trap 'handle_code' ERR

    recon-all --help

    mkdir ${prefix}__recon_all

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        freesurfer: \$(mri_convert -version | grep "freesurfer" | sed -E 's/.* ([0-9.]+).*/\\1/')
    END_VERSIONS
    """
}
